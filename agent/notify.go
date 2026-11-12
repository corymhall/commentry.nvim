package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"

	"github.com/corymhall/commentry.nvim/inbox"
)

// submittedPreview includes only the newest submitted human message, never
// captures or later thread activity. JSON keeps it separate from instructions.
func submittedPreview(message string) (string, bool) {
	start := strings.Index(message, "\n{")
	if !strings.HasPrefix(message, "COMMENTRY_THREAD_V1\n") || start < 0 {
		return "", false
	}
	var saved struct {
		Messages []inbox.Message `json:"messages"`
	}
	if json.Unmarshal([]byte(message[start+1:]), &saved) != nil {
		return "", false
	}
	for _, message := range slices.Backward(saved.Messages) {
		if message.Author != "You" {
			continue
		}
		chars := []rune(message.Body)
		if len(chars) > 1200 {
			return string(chars[:1200]), true
		}
		return string(chars), false
	}
	return "", false
}

// Notify repeats a notification for the same claim. Explicit handoff clears
// the old claim before dispatching the saved request to the new selection.
func Notify(ctx context.Context, directory, project, thread, queueID string, handoff bool) (int, error) {
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
		return 0, fmt.Errorf("attach an existing agent first")
	}
	if _, err = sessionState(ctx, a); err != nil {
		return 0, err
	}
	result, err := store.Execute(ctx, inbox.Request{Action: "read", Thread: thread})
	if err != nil {
		return 0, err
	}
	current := result.(inbox.Thread)
	if current.Project != project {
		return 0, fmt.Errorf("thread belongs to another project")
	}
	return notifyOutstanding(ctx, store, a, directory, current, queueID, handoff)
}

func notifyOutstanding(ctx context.Context, store *inbox.Store, a inbox.Agent, directory string, current inbox.Thread, queueID string, handoff bool) (int, error) {
	for _, q := range current.Queue {
		if q.ID != queueID || (q.Status != "claimed" && q.Status != "failed") {
			continue
		}
		return notifyClaim(ctx, store, a, directory, current.ID, q, handoff)
	}
	return 0, fmt.Errorf("no matching outstanding request; refresh the thread")
}

func notifyClaim(ctx context.Context, store *inbox.Store, a inbox.Agent, directory, thread string, q inbox.Queued, handoff bool) (int, error) {
	directory, err := dataDirectory(directory)
	if err != nil {
		return 0, err
	}
	if q.Author != a.ID {
		if !handoff {
			return 0, fmt.Errorf("request belongs to another agent; confirm an explicit handoff")
		}
		if _, err = store.Execute(ctx, inbox.Request{Action: "handoff", Thread: thread, QueueID: q.ID, ClaimID: q.ClaimID}); err != nil {
			return 0, err
		}
		return dispatchPending(ctx, store, a, directory, thread, q.ID)
	}
	selected, err := store.Agent(ctx, a.Project)
	if err != nil {
		return 0, err
	}
	if selected.ID != a.ID {
		return 0, fmt.Errorf("project agent changed during notification")
	}
	item := map[string]string{"thread": thread, "claim_id": q.ClaimID, "queue_id": q.ID, "message": q.Message, "mode": "queue"}
	if err = deliver(ctx, a, deliveryPrompt(item, a, directory), "queue", directory); err != nil {
		return 0, err
	}
	return 1, nil
}
