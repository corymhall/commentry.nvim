package pibridge

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"path/filepath"

	"github.com/corymhall/commentry.nvim/executor"
	"github.com/corymhall/commentry.nvim/inbox"
)

// Location is non-secret session context for the native extension.
type Location struct {
	Project    string `json:"project"`
	Directory  string `json:"directory"`
	Configured bool   `json:"configured"`
}

// Context resolves the same canonical project and configuration as Neovim.
// No remote request or credential is returned to the extension.
func Context(ctx context.Context, directory, project string) (Location, error) {
	var result Location
	canonical, err := inbox.Project(ctx, project)
	if err != nil {
		return result, err
	}
	if directory == "" {
		directory, err = inbox.DefaultDirectory()
		if err != nil {
			return result, err
		}
	}
	directory, err = filepath.Abs(directory)
	if err != nil {
		return result, err
	}
	_, err = executor.Open(directory)
	if err != nil && !executor.IsUnconfigured(err) {
		return result, err
	}
	return Location{Project: canonical, Directory: directory, Configured: err == nil}, nil
}

type invocation struct {
	Action string                     `json:"action"`
	Input  map[string]json.RawMessage `json:"input"`
}

func decodeCall(reader io.Reader) (invocation, error) {
	var input invocation
	const limit = 4 * 1024 * 1024
	raw, err := io.ReadAll(io.LimitReader(reader, limit+1))
	if err != nil {
		return input, err
	}
	// Reject overflow before parsing. A truncated valid prefix must never
	// become a successful mutation while trailing input is silently ignored.
	if len(raw) > limit {
		return input, fmt.Errorf("pi request exceeds 4 MiB; supply focused excerpts")
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		return input, err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return input, fmt.Errorf("expected one pi request")
	}
	switch input.Action {
	case "requests.read", "requests.context", "list", "read", "create", "reply", "finish", "publish", "attach", "comparison", "revise":
	default:
		return input, fmt.Errorf("unsupported pi operation")
	}
	if input.Input == nil {
		input.Input = map[string]json.RawMessage{}
	}
	return input, nil
}

// Call routes an allowlisted operation through the existing authenticated Go
// client. Native tools do not implement another database or auth stack.
func Call(ctx context.Context, directory, project string, reader io.Reader) (json.RawMessage, error) {
	input, err := decodeCall(reader)
	if err != nil {
		return nil, err
	}
	location, err := Context(ctx, directory, project)
	if err != nil {
		return nil, err
	}
	client, err := executor.Open(location.Directory)
	if err != nil {
		return nil, err
	}
	inspected, err := scopeCall(ctx, client, &input, location.Project)
	if err != nil {
		return nil, err
	}
	if input.Action == "read" && inspected != nil {
		return inspected, nil
	}
	if _, ok := input.Input["author"]; !ok {
		input.Input["author"] = json.RawMessage(`"pi"`)
	}
	var result json.RawMessage
	err = client.Call(ctx, input.Action, input.Input, &result)
	if err == nil && input.Action == "list" {
		return compactList(result)
	}
	return result, err
}

// Discovery should not put saved captures and queue payloads into the model's
// context. Complete thread inspection remains an explicit read operation.
func compactList(raw json.RawMessage) (json.RawMessage, error) {
	var threads []inbox.Thread
	if err := json.Unmarshal(raw, &threads); err != nil {
		return nil, err
	}
	type summary struct {
		ID           string `json:"id"`
		Project      string `json:"project"`
		Title        string `json:"title"`
		Unread       bool   `json:"unread"`
		Resolved     bool   `json:"resolved"`
		MessageCount int    `json:"message_count"`
	}
	result := make([]summary, 0, len(threads))
	for _, thread := range threads {
		result = append(result, summary{thread.ID, thread.Project, thread.Title, thread.Unread, thread.Resolved, len(thread.Messages)})
	}
	return json.Marshal(result)
}

func scopeCall(ctx context.Context, client *executor.Client, input *invocation, project string) (json.RawMessage, error) {
	if raw, ok := input.Input["project"]; ok {
		var requested string
		if json.Unmarshal(raw, &requested) != nil || requested != project {
			return nil, fmt.Errorf("pi tool is scoped to the current project")
		}
	}
	raw, err := json.Marshal(project)
	if err != nil {
		return nil, err
	}
	input.Input["project"] = raw
	// Request-read validates its own manifest. Other thread operations must not
	// accidentally use an ID from another project's context.
	threadJSON, ok := input.Input["thread"]
	if !ok || input.Action == "requests.read" || input.Action == "requests.context" {
		return nil, nil
	}
	var thread string
	if err = json.Unmarshal(threadJSON, &thread); err != nil {
		return nil, err
	}
	var inspected json.RawMessage
	if err = client.Call(ctx, "read", map[string]string{"thread": thread}, &inspected); err != nil {
		return nil, err
	}
	var current struct {
		Project string `json:"project"`
	}
	if err = json.Unmarshal(inspected, &current); err != nil {
		return nil, err
	}
	if current.Project != project {
		return nil, fmt.Errorf("thread belongs to another project")
	}
	// A complete read can reuse this response, including fields introduced
	// by newer backends. Mutations still run only after scope was checked.
	return inspected, nil
}
