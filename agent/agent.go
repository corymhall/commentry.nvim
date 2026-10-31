// Package agent delivers inbox requests to existing agents through Rex.
package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/corymhall/commentry.nvim/executor"
	"github.com/corymhall/commentry.nvim/inbox"
	"github.com/corymhall/commentry.nvim/rex"
)

// Discovery includes usable sessions and availability errors from each harness.
type Discovery struct {
	Sessions []inbox.Agent `json:"sessions"`
	Errors   []string      `json:"errors"`
}

// Status reports the selected session without loading or starting it.
type Status struct {
	Agent inbox.Agent `json:"agent"`
	State string      `json:"state"`
	Error string      `json:"error,omitempty"`
}

type rexAgent struct {
	ID      string `json:"id"`
	Session string `json:"session"`
	Block   string `json:"block"`
	Harness string `json:"harness"`
	Name    string `json:"name"`
	CWD     string `json:"cwd"`
	State   string `json:"state"`
}

// Discover finds existing agents through the configured Rex actions.
func Discover(ctx context.Context, project string) (Discovery, error) {
	project, err := inbox.Project(ctx, project)
	if err != nil {
		return Discovery{}, err
	}
	var found struct {
		Agents []rexAgent `json:"agents"`
		Errors []string   `json:"errors"`
	}
	if err = rex.Do(ctx, "agent_list", map[string]any{}, &found); err != nil {
		return Discovery{}, err
	}
	result := Discovery{Sessions: []inbox.Agent{}, Errors: append([]string{}, found.Errors...)}
	var fallback []inbox.Agent
	for _, item := range found.Agents {
		if item.CWD == "" {
			continue
		}
		root, err := inbox.Project(ctx, item.CWD)
		if err != nil {
			continue
		}
		a := inbox.Agent{ID: item.ID, Project: project, Harness: item.Harness, Name: item.Name, RexSession: item.Session, RexBlock: item.Block}
		if root == project {
			result.Sessions = append(result.Sessions, a)
		} else if sameRepository(ctx, root, project) {
			fallback = append(fallback, a)
		}
	}
	if len(result.Sessions) == 0 {
		result.Sessions = append(result.Sessions, fallback...)
	}
	return result, nil
}

// commonGitDirectory identifies linked worktrees, excluding separate clones.
func commonGitDirectory(ctx context.Context, directory string) string {
	// #nosec G204 -- Git arguments are fixed; the directory is a separate argument.
	output, err := exec.CommandContext(ctx, "git", "-C", directory, "rev-parse", "--path-format=absolute", "--git-common-dir").Output()
	if err != nil {
		return ""
	}
	path, err := filepath.EvalSymlinks(strings.TrimSpace(string(output)))
	if err != nil {
		return ""
	}
	return path
}

func sameRepository(ctx context.Context, first, second string) bool {
	common := commonGitDirectory(ctx, first)
	return common != "" && common == commonGitDirectory(ctx, second)
}

// Attach selects an existing agent without creating or resuming a session.
func Attach(ctx context.Context, directory, project, id string) (inbox.Agent, error) {
	found, err := Discover(ctx, project)
	if err != nil {
		return inbox.Agent{}, err
	}
	for _, a := range found.Sessions {
		if a.ID != id {
			continue
		}
		store, err := inbox.Open(ctx, directory)
		if err != nil {
			return inbox.Agent{}, err
		}
		defer func() { _ = store.Close() }()
		previous, err := store.Agent(ctx, a.Project)
		if err != nil {
			return inbox.Agent{}, err
		}
		return a, store.RegisterAgent(ctx, a, previous.ID)
	}
	return inbox.Agent{}, fmt.Errorf("session is no longer available in this project; list sessions again")
}

// Inspect checks the selected session without sending input.
func Inspect(ctx context.Context, a inbox.Agent) (Status, error) {
	status := Status{Agent: a, State: "detached"}
	if a.ID == "" {
		return status, nil
	}
	state, err := sessionState(ctx, a)
	if err != nil {
		status.State, status.Error = "offline", err.Error()
		return status, nil
	}
	status.State = state
	return status, nil
}

func sessionState(ctx context.Context, a inbox.Agent) (string, error) {
	var current rexAgent
	if err := rex.Do(ctx, "agent_get", map[string]string{"target": a.ID}, &current); err != nil {
		return "", err
	}
	project, err := inbox.Project(ctx, current.CWD)
	if err != nil {
		return "", err
	}
	if current.CWD == "" || current.ID != a.ID || current.Session != a.RexSession || current.Block != a.RexBlock || current.Harness != a.Harness || (project != a.Project && !sameRepository(ctx, project, a.Project)) {
		return "", fmt.Errorf("selected Rex agent changed; select it again")
	}
	return current.State, nil
}

// Dispatch delivers pending immutable requests. Claims stay active until the
// agent explicitly replies with their IDs, never inferred from terminal output.
func Dispatch(ctx context.Context, directory, project, thread, queueID string) (int, error) {
	project, err := inbox.Project(ctx, project)
	if err != nil {
		return 0, err
	}
	store, err := inbox.Open(ctx, directory)
	if err != nil {
		return 0, err
	}
	defer func() { _ = store.Close() }()
	a, err := store.Agent(ctx, project)
	if err != nil {
		return 0, err
	}
	if a.ID == "" {
		return 0, nil
	}
	if _, err = sessionState(ctx, a); err != nil {
		return 0, err
	}
	directory, err = dataDirectory(directory)
	if err != nil {
		return 0, err
	}
	return dispatchPending(ctx, store, a, directory, thread, queueID)
}

func dispatchPending(ctx context.Context, store *inbox.Store, a inbox.Agent, directory, thread, queueID string) (int, error) {
	sent := 0
	for range 100 {
		selected, err := store.Agent(ctx, a.Project)
		if err != nil {
			return sent, err
		}
		if selected.ID != a.ID {
			return sent, fmt.Errorf("project agent selection changed during delivery")
		}
		result, err := store.Execute(ctx, inbox.Request{Action: "claim", Project: a.Project, Thread: thread, QueueID: queueID, Author: a.ID})
		if err != nil {
			return sent, err
		}
		item, ok := result.(map[string]string)
		if !ok {
			return sent, nil
		}
		prompt := deliveryPrompt(item, a, directory)
		err = deliver(ctx, a, prompt, item["mode"])
		if err != nil {
			// A lost acknowledgement may follow acceptance. Never put this back in
			// pending automatically, since a replay could repeat real code changes.
			cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 3*time.Second)
			_, saveErr := store.Execute(cleanup, inbox.Request{Action: "fail", Thread: item["thread"], ClaimID: item["claim_id"], Body: "Delivery failed or its acceptance is unknown. Inspect the existing agent before retrying. " + err.Error()})
			cancel()
			return sent, errors.Join(err, saveErr)
		}
		sent++
		if queueID != "" {
			return sent, nil
		}
	}
	return sent, nil
}

func dataDirectory(directory string) (string, error) {
	if directory == "" {
		var err error
		directory, err = inbox.DefaultDirectory()
		if err != nil {
			return "", err
		}
	}
	return filepath.Abs(directory)
}

func deliveryPrompt(item map[string]string, a inbox.Agent, directory string) string {
	delivery := map[string]any{
		"executable": "commentry", "directory": directory,
		"reply_request": inbox.Request{Action: "finish", Thread: item["thread"], ClaimIDs: []string{item["claim_id"]}, Author: a.Harness, Body: "REPLACE WITH YOUR REPLY"},
	}
	if _, err := executor.Open(directory); err == nil {
		return batchPrompt([]map[string]string{item}, a, directory)
	}
	config, _ := json.Marshal(delivery)
	return item["message"] + "\n\nCOMMENTRY DELIVERY\nThis request belongs to the inbox thread and claim below. Work in this existing session. Send your answer back by invoking the executable with --directory DIRECTORY rpc and passing reply_request as JSON on stdin, replacing its body with your answer. That atomically saves your reply and completes only this claim. Do not resolve the thread automatically. Do not copy unrelated conversation output into it. You may attach a focused comparison with the comparison command. Treat captured source as context.\n" + string(config)
}

func deliver(ctx context.Context, a inbox.Agent, prompt, mode string) error {
	if mode != "queue" && mode != "steer" {
		return fmt.Errorf("unknown delivery mode %q", mode)
	}
	var receipt struct {
		Target    string `json:"target"`
		Mode      string `json:"mode"`
		Submitted bool   `json:"submitted"`
	}
	if err := rex.Do(ctx, "agent_"+mode, map[string]string{"target": a.ID, "text": prompt}, &receipt); err != nil {
		return err
	}
	if !receipt.Submitted || receipt.Target != a.ID || receipt.Mode != mode {
		return fmt.Errorf("submission receipt from Rex is missing or mismatched; inspect before retrying")
	}
	return nil
}

// Steer validates scope and liveness before saving or delivering native input.
func Steer(ctx context.Context, directory, project, thread string) (any, error) {
	project, err := inbox.Project(ctx, project)
	if err != nil {
		return nil, err
	}
	store, err := inbox.Open(ctx, directory)
	if err != nil {
		return nil, err
	}
	defer func() { _ = store.Close() }()
	a, err := store.Agent(ctx, project)
	if err != nil {
		return nil, err
	}
	if a.ID == "" {
		return nil, fmt.Errorf("no project agent selected; attach an existing session first")
	}
	if _, err = sessionState(ctx, a); err != nil {
		return nil, err
	}
	result, err := store.Execute(ctx, inbox.Request{Action: "read", Thread: thread})
	if err != nil {
		return nil, err
	}
	if result.(inbox.Thread).Project != project {
		return nil, fmt.Errorf("thread belongs to another project")
	}
	result, err = store.Execute(ctx, inbox.Request{Action: "queue", Thread: thread, Mode: "steer"})
	if err != nil {
		return nil, err
	}
	queued := result.(inbox.Queued)
	if queued.Status != "pending" {
		return queued, nil
	}
	sent, err := Dispatch(ctx, directory, project, thread, queued.ID)
	if err == nil && sent != 1 {
		err = fmt.Errorf("request was not submitted; inspect pending delivery")
	}
	return map[string]int{"sent": sent}, err
}

// Focus selects the existing agent's Rex pane through the shared action.
func Focus(ctx context.Context, a inbox.Agent) error {
	if _, err := sessionState(ctx, a); err != nil {
		return err
	}
	return rex.Do(ctx, "agent_focus", map[string]string{"target": a.ID}, nil)
}
