package agent

import (
	"strings"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// TestNotifyKeepsClaimAndHandoffInvalidatesOldClaim
// verifies delivery recovery invariants.
func TestNotifyKeepsClaimAndHandoffInvalidatesOldClaim(t *testing.T) {
	f := fakeRex(t)
	thread := f.queued(t)
	if _, err := Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := Dispatch(t.Context(), f.directory, f.project, thread, ""); err != nil {
		t.Fatal(err)
	}
	before := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	q := before.Queue[0]
	if n, err := Notify(t.Context(), f.directory, f.project, thread, q.ID, false); err != nil || n != 1 {
		t.Fatalf("notify=%d %v", n, err)
	}
	after := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	if len(after.Queue) != 1 || after.Queue[0].ClaimID != q.ClaimID || len(after.Messages) != len(before.Messages) {
		t.Fatal("reminder duplicated work")
	}
	// Selecting another running session does not silently reassign outstanding work.
	f.native.Agent.ID = "session/block/456"
	f.save(t)
	if _, err := Attach(t.Context(), f.directory, f.project, f.native.Agent.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := Notify(t.Context(), f.directory, f.project, thread, q.ID, false); err == nil {
		t.Fatal("silent handoff")
	}
	if n, err := Notify(t.Context(), f.directory, f.project, thread, q.ID, true); err != nil || n != 1 {
		t.Fatalf("handoff=%d %v", n, err)
	}
	current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	if len(current.Queue) != 1 || current.Queue[0].ClaimID == q.ClaimID || current.Queue[0].Message != q.Message {
		t.Fatal("handoff did not preserve request")
	}
	if _, err := f.store.Execute(t.Context(), inbox.Request{Action: "finish", Thread: thread, ClaimIDs: []string{q.ClaimID}, Author: "codex", Body: "stale answer"}); err == nil {
		t.Fatal("old claim finished after handoff")
	}
}

// TestNativePiFailureNeverPastes verifies fallback requires an explicit choice.
func TestNativePiFailureNeverPastes(t *testing.T) {
	f := fakeRex(t)
	f.native.Agent.Harness, f.agent.Harness = "pi", "pi"
	f.save(t)
	t.Setenv("COMMENTRY_PI_RUNTIME_DIR", t.TempDir())
	thread := f.queued(t)
	if _, err := Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := Dispatch(t.Context(), f.directory, f.project, thread, ""); err == nil {
		t.Fatal("missing native receiver accepted")
	}
	if len(f.deliveries(t)) != 0 {
		t.Fatal("native failure fell back to terminal paste")
	}
	current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	f.execute(t, inbox.Request{Action: "retry", Thread: thread, QueueID: current.Queue[0].ID})
	t.Setenv("COMMENTRY_PI_TRANSPORT", "rex")
	if n, err := Dispatch(t.Context(), f.directory, f.project, thread, ""); err != nil || n != 1 {
		t.Fatalf("explicit terminal fallback=%d %v", n, err)
	}
	if len(f.deliveries(t)) != 1 {
		t.Fatal("explicit terminal fallback not submitted")
	}
}

// TestSubmittedPreviewIsBoundedAndFrozen verifies delivery recovery invariants.
func TestSubmittedPreviewIsBoundedAndFrozen(t *testing.T) {
	message := "COMMENTRY_THREAD_V1\n{}"
	preview, truncated := submittedPreview(message)
	if preview != "" || truncated {
		t.Fatal("invented preview")
	}
	message = "COMMENTRY_THREAD_V1\n{\"messages\":[{\"author\":\"You\",\"body\":\"" + strings.Repeat("界", 1300) + "\"}]}"
	preview, truncated = submittedPreview(message)
	if len([]rune(preview)) != 1200 || !truncated {
		t.Fatal("preview not Unicode bounded")
	}
}
