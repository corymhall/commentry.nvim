package inbox_test

import (
	"reflect"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// TestSessionActivityRetainsActualWorkersAcrossRetries checks attribution.
// Retries and failed actions must not rewrite history.
func TestSessionActivityRetainsActualWorkersAcrossRetries(t *testing.T) {
	s := openStore(t, t.TempDir())
	project := t.TempDir()
	first := &inbox.Session{Harness: "pi", ID: "first-session"}
	second := &inbox.Session{Harness: "pi", ID: "second-session"}
	id := run(t, s, inbox.Request{Action: "create", Project: project, Body: "question", Session: first}).(string)
	run(t, s, inbox.Request{Action: "queue", Thread: id})
	claim := run(t, s, inbox.Request{Action: "claim", Project: project, Author: "target-worker"}).(map[string]string)
	ack := inbox.Request{Action: "acknowledge", Thread: id, ClaimID: claim["claim_id"], Session: first}
	run(t, s, ack)
	run(t, s, ack)
	ack.Session = second
	run(t, s, ack)
	finish := inbox.Request{Action: "finish", Thread: id, ClaimIDs: []string{claim["claim_id"]}, Author: "pi", Body: "answer", RequestID: "durable", Session: second}
	original := run(t, s, finish).(inbox.Event)
	finish.Session = first
	if replay := run(t, s, finish).(inbox.Event); replay.ID != original.ID {
		t.Fatal("reply retry changed receipt")
	}
	current := run(t, s, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(current.SessionActivity) != 4 || len(current.Messages) != 2 || current.Resolved {
		t.Fatalf("wrong thread history: %+v", current)
	}
	for i, want := range []string{first.ID, first.ID, second.ID, second.ID} {
		if current.SessionActivity[i].Session.ID != want {
			t.Fatalf("wrong actor at %d", i)
		}
	}
	if current.SessionActivity[3].EventID != original.ID || !reflect.DeepEqual(current.SessionActivity[3].ClaimIDs, finish.ClaimIDs) {
		t.Fatal("missing message or claim links")
	}
	if current.Queue[0].Author != "target-worker" || current.Queue[0].Status != "complete" {
		t.Fatal("delivery worker changed")
	}
	before := current.SessionActivity
	_, err := s.Execute(t.Context(), inbox.Request{Action: "finish", Thread: id, ClaimIDs: []string{"missing"}, Body: "invalid", Session: first})
	if err == nil {
		t.Fatal("missing claim accepted")
	}
	current = run(t, s, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if !reflect.DeepEqual(before, current.SessionActivity) {
		t.Fatal("failed action left provenance")
	}

	pending := run(t, s, inbox.Request{Action: "create", Project: project, Body: "draft", Pending: true}).(string)
	draft := run(t, s, inbox.Request{Action: "read", Thread: pending}).(inbox.Thread)
	edit := run(t, s, inbox.Request{Action: "edit-pending", Thread: pending, ExpectedMessage: draft.Messages[0].ID, Body: "updated draft", Session: first}).(inbox.Event)
	draft = run(t, s, inbox.Request{Action: "read", Thread: pending}).(inbox.Thread)
	if len(draft.SessionActivity) != 1 || draft.SessionActivity[0].EventID != edit.ID || draft.SessionActivity[0].Session != *first {
		t.Fatal("pending edit lost acting session")
	}
}
