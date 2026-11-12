package inbox_test

import (
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// TestFinishRetryAndReceiptAreIndependentOfHumanReadState
// verifies delivery recovery invariants.
func TestFinishRetryAndReceiptAreIndependentOfHumanReadState(t *testing.T) {
	s := openStore(t, t.TempDir())
	project := t.TempDir()
	id := create(t, s, project)
	run(t, s, inbox.Request{Action: "queue", Thread: id})
	c := run(t, s, inbox.Request{Action: "claim", Project: project, Author: "worker"}).(map[string]string)
	run(t, s, inbox.Request{Action: "acknowledge", Thread: id, ClaimID: c["claim_id"]})
	current := run(t, s, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if current.Queue[0].AcknowledgedAt == "" || current.Unread || current.Queue[0].Status != "claimed" {
		t.Fatal("ack changed human or completion state")
	}
	r := inbox.Request{Action: "finish", Thread: id, ClaimIDs: []string{c["claim_id"]}, Author: "codex", Body: "answer", RequestID: "durable-answer"}
	first := run(t, s, r).(inbox.Event)
	again := run(t, s, r).(inbox.Event)
	if first.ID != again.ID {
		t.Fatal("retry receipt changed")
	}
	current = run(t, s, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(current.Messages) != 2 || !current.Unread || current.Resolved {
		t.Fatal("finish retry duplicated or resolved conversation")
	}
	r.Body = "changed"
	if _, err := s.Execute(t.Context(), r); err == nil {
		t.Fatal("changed retry accepted")
	}
}
