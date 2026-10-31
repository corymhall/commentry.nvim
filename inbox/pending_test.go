package inbox_test

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// TestPendingCommentFreezesWhenQueued protects the editable send boundary.
func TestPendingCommentFreezesWhenQueued(t *testing.T) {
	t.Parallel()
	directory := t.TempDir()
	store := openStore(t, directory)
	project := t.TempDir()
	source := inbox.Source{Kind: "file", Path: "example.lua", First: 1, Last: 1, Lines: []string{"original code"}}
	id := run(t, store, inbox.Request{Action: "create", Project: project, Source: &source, Body: "Draft", Pending: true}).(string)
	original := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	reject := func(r inbox.Request) {
		t.Helper()
		if _, err := store.Execute(t.Context(), r); err == nil {
			t.Fatalf("accepted forbidden mutation: %+v", r)
		}
	}
	reject(inbox.Request{Action: "reply", Thread: id, Body: "Premature reply"})
	reject(inbox.Request{Action: "edit-pending", Thread: id, Author: "Agent", ExpectedMessage: original.Messages[0].ID, Body: "Agent edit"})
	run(t, store, inbox.Request{Action: "edit-pending", Thread: id, ExpectedMessage: original.Messages[0].ID, Body: "Final question\nMore detail"})
	reject(inbox.Request{Action: "edit-pending", Thread: id, ExpectedMessage: original.Messages[0].ID, Body: "Stale edit"})
	// A second client must see the persisted draft, including its version.
	second := openStore(t, directory)
	edited := run(t, second, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if !edited.Pending || edited.Title != "Final question" || !reflect.DeepEqual(edited.Source, source) {
		t.Fatalf("invalid pending state: %+v", edited)
	}
	// A failed queue transaction must not freeze the draft.
	reject(inbox.Request{Action: "queue", Thread: id, Mode: "invalid"})
	if !run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread).Pending {
		t.Fatal("failed send froze draft")
	}
	q := run(t, store, inbox.Request{Action: "queue", Thread: id}).(inbox.Queued)
	if got := queuedMessages(t, q)[0].Body; got != "Final question\nMore detail" {
		t.Fatalf("queued body = %q, want complete edited question", got)
	}
	reject(inbox.Request{Action: "edit-pending", Thread: id, ExpectedMessage: edited.Messages[0].ID, Body: "Too late"})
	run(t, store, inbox.Request{Action: "cancel", Thread: id, QueueID: q.ID})
	reject(inbox.Request{Action: "discard-pending", Thread: id, ExpectedMessage: edited.Messages[0].ID})
	run(t, store, inbox.Request{Action: "reply", Thread: id, Body: "Follow-up"})
	sent := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if sent.Pending || sent.Messages[0].Body != edited.Messages[0].Body || len(sent.Messages) != 2 {
		t.Fatalf("sent history changed: %+v", sent)
	}
}

// TestQueueRacesPendingEdit protects the snapshot against independent writers.
func TestQueueRacesPendingEdit(t *testing.T) {
	t.Parallel()
	directory := t.TempDir()
	editor, sender := openStore(t, directory), openStore(t, directory)
	project := t.TempDir()
	for range 10 {
		id := run(t, editor, inbox.Request{Action: "create", Project: project, Body: "Original", Pending: true}).(string)
		original := run(t, editor, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
		start := make(chan struct{})
		edited := make(chan error, 1)
		go func() {
			<-start
			_, err := editor.Execute(t.Context(), inbox.Request{Action: "edit-pending", Thread: id, ExpectedMessage: original.Messages[0].ID, Body: "Revised"})
			edited <- err
		}()
		close(start)
		queued, err := sender.Execute(t.Context(), inbox.Request{Action: "queue", Thread: id})
		editErr := <-edited
		if err != nil {
			t.Fatal(err)
		}
		want := "Revised"
		if editErr != nil {
			if !strings.Contains(editErr.Error(), "only your unsent pending comment") {
				t.Fatalf("unexpected concurrent edit failure: %v", editErr)
			}
			want = "Original"
		}
		current := run(t, editor, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
		if current.Pending || current.Messages[0].Body != want || queuedMessages(t, queued.(inbox.Queued))[0].Body != want {
			t.Fatalf("queue and edit disagreed: edit error=%v, current=%+v, queued=%+v", editErr, current, queued)
		}
	}
}

// queuedMessages reads the submitted snapshot, independent of current state.
func queuedMessages(t *testing.T, q inbox.Queued) []inbox.Message {
	t.Helper()
	start := strings.Index(q.Message, "\n{")
	if start < 0 {
		t.Fatal("queued request has no JSON snapshot")
	}
	var snapshot struct {
		Messages []inbox.Message `json:"messages"`
	}
	if err := json.Unmarshal([]byte(q.Message[start+1:]), &snapshot); err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Messages) == 0 {
		t.Fatal("queued snapshot has no discussion")
	}
	return snapshot.Messages
}

// TestDiscardPendingPublishesChange notifies readers without deleting history.
func TestDiscardPendingPublishesChange(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	id := run(t, store, inbox.Request{Action: "create", Project: t.TempDir(), Body: "Discard me", Pending: true}).(string)
	original := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	revision := run(t, store, inbox.Request{Action: "revision"}).(int64)
	run(t, store, inbox.Request{Action: "discard-pending", Thread: id, ExpectedMessage: original.Messages[0].ID})
	if _, err := store.Execute(t.Context(), inbox.Request{Action: "read", Thread: id}); err == nil {
		t.Fatal("discarded thread still readable")
	}
	changes := run(t, store, inbox.Request{Action: "changes", Cursor: revision}).(inbox.Changes)
	if len(changes.Changes) != 1 || changes.Changes[0].Kind != "discard-pending" {
		t.Fatalf("missing discard notification: %+v", changes)
	}
	legacy := create(t, store, t.TempDir())
	thread := run(t, store, inbox.Request{Action: "read", Thread: legacy}).(inbox.Thread)
	if _, err := store.Execute(t.Context(), inbox.Request{Action: "edit-pending", Thread: legacy, ExpectedMessage: thread.Messages[0].ID, Body: "Not a draft"}); err == nil {
		t.Fatal("legacy conversation became editable")
	}
}
