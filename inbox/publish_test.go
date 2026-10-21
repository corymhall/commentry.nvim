package inbox_test

import (
	"reflect"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// TestPublicationLostReceiptAndAtomicFailure covers rollback and safe replay.
func TestPublicationLostReceiptAndAtomicFailure(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	project := t.TempDir()
	r := inbox.Request{Action: "publish", Project: project, Author: "codex", RequestID: "review-1", Items: []inbox.PublishItem{
		{Key: "one", Title: "Eight workers", Body: "Concurrency increases.", Source: &inbox.Source{Kind: "file", Path: "worker.ts", First: 400, Last: 400, ExcerptFirst: 400, Lines: []string{"workers = 8;"}}, Comparisons: []inbox.PublishComparison{{Key: "count", Label: "Worker count", Before: "4", After: "8"}}, PrimaryComparison: "count"},
		{Key: "two", Title: "JSON logs", Body: "Logs change format.", Attachments: []inbox.PublishAttachment{{Label: "Logger", Source: inbox.Source{Kind: "file", Path: "logger.ts", First: 900, Last: 900, ExcerptFirst: 900, Lines: []string{"format = 'json';"}}}}},
	}}
	r.Items[1].Attachments[0].Source.Last = 901
	if _, err := store.Execute(t.Context(), r); err == nil {
		t.Fatal("accepted excerpt that does not cover selection")
	}
	if revision := run(t, store, inbox.Request{Action: "revision"}).(int64); revision != 0 {
		t.Fatal("failed publication committed partial changes")
	}
	if receipt := run(t, store, inbox.Request{Action: "publication", Project: project, RequestID: r.RequestID}).(inbox.PublishReceipt); receipt.Status != "missing" {
		t.Fatal("failed publication left a receipt")
	}
	r.Items[1].Attachments[0].Source.Last = 900
	receipt := run(t, store, r).(inbox.PublishReceipt)
	run(t, store, inbox.Request{Action: "reply", Thread: receipt.Items[0].Thread, Body: "Keep four for now."})
	run(t, store, inbox.Request{Action: "resolve", Thread: receipt.Items[0].Thread, Resolved: new(true)})
	revision := run(t, store, inbox.Request{Action: "revision"}).(int64)
	if retry := run(t, store, r).(inbox.PublishReceipt); !reflect.DeepEqual(receipt, retry) {
		t.Fatal("retry changed saved IDs")
	}
	if status := run(t, store, inbox.Request{Action: "publication", Project: project, RequestID: r.RequestID}).(inbox.PublishReceipt); !reflect.DeepEqual(receipt, status) {
		t.Fatal("lookup did not recover receipt")
	}
	r.Items[0].Body = "Different review"
	if _, err := store.Execute(t.Context(), r); err == nil {
		t.Fatal("accepted changed content at existing request ID")
	}
	if current := run(t, store, inbox.Request{Action: "revision"}).(int64); current != revision {
		t.Fatal("replay mutated the inbox")
	}
	thread := run(t, store, inbox.Request{Action: "read", Thread: receipt.Items[0].Thread}).(inbox.Thread)
	if !thread.Resolved || thread.Messages[len(thread.Messages)-1].Body != "Keep four for now." || thread.PrimaryComparison != receipt.Items[0].Comparisons[0].ID {
		t.Fatal("publication damaged human discussion or evidence")
	}
}
