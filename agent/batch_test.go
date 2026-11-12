package agent

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// TestBatchNotificationKeepsClaimsAndSnapshotsSeparate checks batch scope.
func TestBatchNotificationKeepsClaimsAndSnapshotsSeparate(t *testing.T) {
	f := fakeRex(t)
	ids := []string{}
	threads := []string{}
	for i := range 5 {
		captured := fmt.Sprintf("Original capture %d", i)
		thread := f.execute(t, inbox.Request{Action: "create", Project: f.project, Body: fmt.Sprintf("Question %d", i), Text: &captured}).(string)
		queued := f.execute(t, inbox.Request{Action: "queue", Thread: thread}).(inbox.Queued)
		ids = append(ids, queued.ID)
		threads = append(threads, thread)
	}
	untouched := f.queued(t)
	if _, err := Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	sent, err := DispatchBatch(t.Context(), f.directory, f.project, ids)
	if err != nil || sent != 5 {
		t.Fatalf("batch sent=%d, err=%v", sent, err)
	}
	items := batchNotification(t, f)
	checkBatchClaims(t, f, items, threads)
	first := items[0]
	f.execute(t, inbox.Request{Action: "finish", Thread: first.Thread, ClaimIDs: first.ClaimIDs, Author: "codex", Body: "Answer only this item"})
	checkBatchCompletion(t, f, threads)
	if sent, err = DispatchBatch(t.Context(), f.directory, f.project, ids); err != nil || sent != 0 || len(f.deliveries(t)) != 1 {
		t.Fatalf("batch replayed: %d, %v", sent, err)
	}
	current := f.execute(t, inbox.Request{Action: "read", Thread: untouched}).(inbox.Thread)
	if current.Queue[0].Status != "pending" {
		t.Fatal("batch consumed an unselected request")
	}
}

// TestUncertainBatchRetainsEveryClaimWithoutReplay checks lost receipts.
func TestUncertainBatchRetainsEveryClaimWithoutReplay(t *testing.T) {
	f := fakeRex(t)
	first, second := f.queued(t), f.queued(t)
	ids := []string{}
	for _, thread := range []string{first, second} {
		current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
		ids = append(ids, current.Queue[0].ID)
	}
	if _, err := Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	f.native.Reject = true
	f.save(t)
	if _, err := DispatchBatch(t.Context(), f.directory, f.project, ids); err == nil {
		t.Fatal("expected uncertain delivery")
	}
	for _, thread := range []string{first, second} {
		current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
		q := current.Queue[0]
		if q.Status != "failed" || q.ClaimID == "" {
			t.Fatalf("lost uncertain claim: %+v", q)
		}
	}
	if sent, err := DispatchBatch(t.Context(), f.directory, f.project, ids); err != nil || sent != 0 || len(f.deliveries(t)) != 1 {
		t.Fatalf("uncertain batch replayed: %d, %v", sent, err)
	}
	current := f.execute(t, inbox.Request{Action: "read", Thread: first}).(inbox.Thread)
	f.execute(t, inbox.Request{Action: "finish", Thread: first, ClaimIDs: []string{current.Queue[0].ClaimID}, Author: "codex", Body: "Late answer to first item"})
	current = f.execute(t, inbox.Request{Action: "read", Thread: second}).(inbox.Thread)
	if current.Queue[0].Status != "failed" || len(current.Messages) != 1 {
		t.Fatal("late answer changed another thread")
	}
}

func batchNotification(t *testing.T, f *fixture) []batchItem {
	t.Helper()
	writes := f.deliveries(t)
	if len(writes) != 1 || writes[0]["action"] != "agent_queue" {
		t.Fatalf("expected one native queue notification, got %v", writes)
	}
	prompt := writes[0]["text"]
	if strings.Contains(prompt, "Original capture") || !strings.Contains(prompt, "Question") || strings.Contains(prompt, "COMMENTRY_THREAD_V1") {
		t.Fatal("notification must include human previews but exclude captures and queue snapshots")
	}
	var notification struct {
		Project string      `json:"project"`
		Items   []batchItem `json:"items"`
	}
	start := strings.Index(prompt, "\n{")
	if start < 0 {
		t.Fatal("missing batch manifest")
	}
	if err := json.Unmarshal([]byte(prompt[start+1:]), &notification); err != nil {
		t.Fatal(err)
	}
	if notification.Project != f.project || len(notification.Items) != 5 {
		t.Fatalf("wrong batch scope: %+v", notification)
	}
	return notification.Items
}

func checkBatchClaims(t *testing.T, f *fixture, items []batchItem, threads []string) {
	t.Helper()
	for i, item := range items {
		current := f.execute(t, inbox.Request{Action: "read", Thread: item.Thread}).(inbox.Thread)
		q := current.Queue[0]
		if item.Thread != threads[i] || len(item.ClaimIDs) != 1 || item.ClaimIDs[0] != q.ClaimID || q.Status != "claimed" {
			t.Fatalf("wrong claim for item %d: %+v", i, item)
		}
		if !strings.Contains(q.Message, fmt.Sprintf("Original capture %d", i)) {
			t.Fatal("submitted snapshot was lost")
		}
	}
}

func checkBatchCompletion(t *testing.T, f *fixture, threads []string) {
	t.Helper()
	for i, thread := range threads {
		current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
		if current.Resolved || (i == 0 && (len(current.Messages) != 2 || current.Queue[0].Status != "complete")) || (i > 0 && (len(current.Messages) != 1 || current.Queue[0].Status != "claimed")) {
			t.Fatalf("completion leaked between threads: %+v", current)
		}
	}
}
