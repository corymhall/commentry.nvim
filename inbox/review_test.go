package inbox_test

import (
	"strings"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// Revisions preserve captures, human conversation, and queued work.
func TestReviewRevisionPreservesConversationAndRejectsStaleWriters(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	id := run(t, store, inbox.Request{Action: "create", Project: t.TempDir(), Title: "Original question", Body: "Explain this"}).(string)
	before, after := "literal reference", "resolved name"
	comparison := run(t, store, inbox.Request{Action: "comparison", Thread: id, Author: "Agent", Label: "Generated documentation", Before: &before, After: &after}).(inbox.Event)
	queued := run(t, store, inbox.Request{Action: "queue", Thread: id}).(inbox.Queued)
	revision := run(t, store, inbox.Request{Action: "revise", Thread: id, Author: "Agent", Title: "References render as literal markup", Body: "This fix resolves references.", PrimaryComparison: &comparison.ID}).(inbox.Review)
	run(t, store, inbox.Request{Action: "reply", Thread: id, Body: "Can you keep code formatting?"})
	for _, request := range []inbox.Request{
		{Action: "revise", Thread: id, Author: "Agent", Body: "Stale replacement"},
		{Action: "revise", Thread: id, Author: "Other", ExpectedReview: revision.ID, Body: "Another author's replacement"},
		{Action: "revise", Thread: id, Author: "Agent", ExpectedReview: revision.ID, PrimaryComparison: new("missing")},
		{Action: "comparison", Thread: id, Author: "Other", ComparisonID: comparison.ID, Label: "Overwrite", Before: &before, After: &after},
	} {
		if _, err := store.Execute(t.Context(), request); err == nil {
			t.Fatalf("accepted unsafe revision: %+v", request)
		}
	}
	run(t, store, inbox.Request{Action: "revise", Thread: id, Author: "Agent", ExpectedReview: revision.ID, Body: "References resolve, but names lose code formatting."})
	current := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if current.Review.Summary != "References resolve, but names lose code formatting." || current.Title != revision.Title || len(current.ReviewHistory) != 2 || len(current.Messages) != 2 || current.Messages[1].Body != "Can you keep code formatting?" || current.Queue[0].Message != queued.Message || len(current.Source.Lines) != 0 || current.Resolved {
		t.Fatalf("revision damaged conversation state: %+v", current)
	}
	read := true
	run(t, store, inbox.Request{Action: "read-state", Thread: id, Read: &read, Seen: current.Incoming})
	after = "resolved name with code formatting"
	replacement := run(t, store, inbox.Request{Action: "comparison", Thread: id, Author: "Agent", ComparisonID: comparison.ID, Label: "Generated documentation", Before: &before, After: &after}).(inbox.Event)
	current = run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if replacement.ID != comparison.ID || len(current.Comparisons) != 1 || current.Comparisons[0].After != after || current.PrimaryComparison != comparison.ID || len(current.ComparisonHistory) != 1 || current.ComparisonHistory[0].After != "resolved name" || !current.Unread {
		t.Fatalf("replacement lost evidence identity/history or unread state: %+v", current)
	}
	next := run(t, store, inbox.Request{Action: "queue", Thread: id}).(inbox.Queued)
	if next.ID == queued.ID || !strings.Contains(next.Message, current.Review.Summary) {
		t.Fatal("new request omitted the current review")
	}
}

// Archiving withdraws misleading evidence without erasing its history.
func TestArchiveComparisonPreservesHistoryAndClearsPrimary(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	id := create(t, store, t.TempDir())
	before, after := "guessed original", "current output"
	comparison := run(t, store, inbox.Request{Action: "comparison", Thread: id, Author: "Agent", Label: "Unverified baseline", Before: &before, After: &after}).(inbox.Event)
	run(t, store, inbox.Request{Action: "revise", Thread: id, Author: "Agent", Title: "Output formatting needs verification", Body: "Original generated output is unavailable.", PrimaryComparison: &comparison.ID})
	queued := run(t, store, inbox.Request{Action: "queue", Thread: id}).(inbox.Queued)
	current := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	read := true
	run(t, store, inbox.Request{Action: "read-state", Thread: id, Read: &read, Seen: current.Incoming})
	if _, err := store.Execute(t.Context(), inbox.Request{Action: "archive-comparison", Thread: id, Author: "Other", ComparisonID: comparison.ID}); err == nil {
		t.Fatal("another author withdrew comparison")
	}
	current = run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(current.Comparisons) != 1 || current.PrimaryComparison != comparison.ID || current.Unread {
		t.Fatal("failed archive modified evidence or unread state")
	}
	event := run(t, store, inbox.Request{Action: "archive-comparison", Thread: id, Author: "Agent", ComparisonID: comparison.ID}).(inbox.Event)
	current = run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(current.Comparisons) != 0 || current.PrimaryComparison != "" || len(current.ComparisonHistory) != 1 || current.ComparisonHistory[0].Before != before || current.Incoming != event.ID || !current.Unread || current.Queue[0].Message != queued.Message || len(current.Messages) != 1 || current.Resolved {
		t.Fatalf("archive damaged evidence history or conversation: %+v", current)
	}
	if _, err := store.Execute(t.Context(), inbox.Request{Action: "archive-comparison", Thread: id, Author: "Agent", ComparisonID: comparison.ID}); err == nil {
		t.Fatal("archived an inactive comparison twice")
	}
}
