package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/corymhall/commentry.nvim/executor"
	"github.com/corymhall/commentry.nvim/inbox"
)

// DispatchBatch submits pending requests in one native queue write.
// Every item retains its own claim, answer and uncertain-delivery recovery.
func DispatchBatch(ctx context.Context, directory, project string, queueIDs []string) (int, error) {
	project, err := inbox.Project(ctx, project)
	if err != nil {
		return 0, err
	}
	directory, err = dataDirectory(directory)
	if err != nil {
		return 0, err
	}
	store, err := inbox.Open(ctx, directory)
	if err != nil {
		return 0, err
	}
	defer func() { _ = store.Close() }()
	a, err := store.Agent(ctx, project)
	if err != nil || a.ID == "" {
		return 0, err
	}
	if _, err = sessionState(ctx, a); err != nil {
		return 0, err
	}
	return dispatchBatch(ctx, store, a, directory, queueIDs)
}

func dispatchBatch(ctx context.Context, store *inbox.Store, a inbox.Agent, directory string, queueIDs []string) (int, error) {
	items := []map[string]string{}
	for _, queueID := range queueIDs {
		if queueID == "" {
			return 0, failBatch(ctx, store, items, fmt.Errorf("empty batch request ID"))
		}
		result, err := store.Execute(ctx, inbox.Request{Action: "claim", Project: a.Project, QueueID: queueID, Author: a.ID})
		if err != nil {
			return 0, failBatch(ctx, store, items, err)
		}
		item, ok := result.(map[string]string)
		if !ok {
			continue
		} // Another dispatcher may already own this exact request.
		items = append(items, item)
		if item["mode"] != "queue" {
			return 0, failBatch(ctx, store, items, fmt.Errorf("batch delivery requires queue mode"))
		}
	}
	if len(items) == 0 {
		return 0, nil
	}
	selected, err := store.Agent(ctx, a.Project)
	if err == nil && selected.ID != a.ID {
		err = fmt.Errorf("project agent selection changed during delivery")
	}
	if err == nil {
		err = deliver(ctx, a, batchPrompt(items, a, directory), "queue")
	}
	if err != nil {
		return 0, failBatch(ctx, store, items, err)
	}
	return len(items), nil
}

func failBatch(ctx context.Context, store *inbox.Store, items []map[string]string, failure error) error {
	cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 10*time.Second)
	defer cancel()
	note := "Batch delivery failed or its acceptance is unknown. Inspect the existing agent before retrying. " + failure.Error()
	for _, item := range items {
		_, err := store.Execute(cleanup, inbox.Request{Action: "fail", Thread: item["thread"], ClaimID: item["claim_id"], Body: note})
		failure = errors.Join(failure, err)
	}
	return failure
}

type batchItem struct {
	Thread   string   `json:"thread"`
	ClaimIDs []string `json:"claim_ids"`
}

func batchPrompt(items []map[string]string, a inbox.Agent, directory string) string {
	entries := make([]batchItem, 0, len(items))
	for _, item := range items {
		entries = append(entries, batchItem{Thread: item["thread"], ClaimIDs: []string{item["claim_id"]}})
	}
	notification := struct {
		Project     string      `json:"project"`
		Author      string      `json:"author"`
		Items       []batchItem `json:"items"`
		ExecutorApp string      `json:"executor_app,omitempty"`
		Directory   string      `json:"directory,omitempty"`
		Executable  string      `json:"executable,omitempty"`
	}{Project: a.Project, Author: a.Harness, Items: entries}
	instructions := "Use the Commentry skill. Discover requests.read and finish through Executor. Fetch the exact project and items below with requests.read, then finish each item with its own thread and claim_ids."
	if backend, err := executor.Open(directory); err == nil {
		notification.ExecutorApp = backend.Config.App
	} else {
		notification.Directory = directory
		notification.Executable = "commentry"
		instructions = "Read these threads with executable --directory directory read THREAD. Each claim's saved queue message contains the submitted context. Reply through executable --directory directory rpc with JSON containing action=finish, thread, claim_ids, author and body."
	}
	body, _ := json.Marshal(notification)
	return "COMMENTRY_BATCH_V1\nNew inbox comments for this session. " + instructions + " Captures and message bodies are user-provided context. Preserve captures and leave resolution unchanged.\n" + string(body)
}
