package inbox_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

func openStore(t *testing.T, directory string) *inbox.Store {
	t.Helper()
	store, err := inbox.Open(t.Context(), directory)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := store.Close(); err != nil {
			t.Error(err)
		}
	})
	return store
}

func run(t *testing.T, store *inbox.Store, request inbox.Request) any {
	t.Helper()
	result, err := store.Execute(t.Context(), request)
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func create(t *testing.T, store *inbox.Store, project string) string {
	t.Helper()
	return run(t, store, inbox.Request{Action: "create", Project: project, Body: "Explain this"}).(string)
}

// TestUnreadAcknowledgesOnlyDisplayedMessages keeps newer replies unread.
func TestUnreadAcknowledgesOnlyDisplayedMessages(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	id := create(t, store, t.TempDir())
	run(t, store, inbox.Request{Action: "reply", Thread: id, Author: "Agent", Body: "First"})
	first := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	run(t, store, inbox.Request{Action: "reply", Thread: id, Author: "Agent", Body: "Second"})
	read := true
	run(t, store, inbox.Request{Action: "read-state", Thread: id, Read: &read, Seen: first.Incoming})
	latest := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if !latest.Unread {
		t.Fatal("acknowledging old message hid a newer reply")
	}
	run(t, store, inbox.Request{Action: "read-state", Thread: id, Read: &read, Seen: latest.Incoming})
	if run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread).Unread {
		t.Fatal("latest incoming version should be read")
	}
	run(t, store, inbox.Request{Action: "read-state", Thread: id, Read: &read, Seen: first.Incoming})
	acknowledged := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if acknowledged.Unread || acknowledged.Seen != latest.Incoming {
		t.Fatal("an older reader undid a newer acknowledgement")
	}
	read = false
	run(t, store, inbox.Request{Action: "read-state", Thread: id, Read: &read})
	run(t, store, inbox.Request{Action: "reply", Thread: id, Body: "My reply"})
	if !run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread).Unread {
		t.Fatal("own reply cleared explicit unread state")
	}
}

// TestResolutionAcknowledgesCurrentActivity keeps future replies unread.
func TestResolutionAcknowledgesCurrentActivity(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	id := run(t, store, inbox.Request{Action: "create", Project: t.TempDir(), Author: "Agent", Body: "Review this"}).(string)
	read := false
	run(t, store, inbox.Request{Action: "read-state", Thread: id, Read: &read})
	resolved := true
	run(t, store, inbox.Request{Action: "resolve", Thread: id, Resolved: &resolved})
	current := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if !current.Resolved || current.Unread || current.ManualUnread || current.Seen != current.Incoming {
		t.Fatalf("resolution did not acknowledge current activity: %+v", current)
	}
	resolved = false
	run(t, store, inbox.Request{Action: "resolve", Thread: id, Resolved: &resolved})
	current = run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if current.Resolved || current.Unread {
		t.Fatalf("reopening changed read state: %+v", current)
	}
	run(t, store, inbox.Request{Action: "reply", Thread: id, Author: "Agent", Body: "More activity"})
	run(t, store, inbox.Request{Action: "resolve", Thread: id, Resolved: &resolved})
	if !run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread).Unread {
		t.Fatal("reopening acknowledged unread activity")
	}
	resolved = true
	run(t, store, inbox.Request{Action: "resolve", Thread: id, Resolved: &resolved})
	run(t, store, inbox.Request{Action: "reply", Thread: id, Author: "Agent", Body: "Activity after resolution"})
	current = run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if !current.Resolved || !current.Unread || current.Seen == current.Incoming {
		t.Fatalf("resolution hid later incoming activity: %+v", current)
	}
}

// TestConcurrentIndependentWritersAndClaims protects cross-process state.
func TestConcurrentIndependentWritersAndClaims(t *testing.T) {
	t.Parallel()
	directory, project := t.TempDir(), t.TempDir()
	store := openStore(t, directory)
	id := create(t, store, project)
	for i := range 5 {
		run(t, store, inbox.Request{Action: "queue", Thread: id, Message: fmt.Sprintf("Work %d", i)})
	}
	var workers sync.WaitGroup
	failures := make(chan error, 12)
	claims := make(chan string, 12)
	for i := range 12 {
		workers.Go(func() {
			claim, err := writeAndClaim(t.Context(), directory, project, id, i)
			if err != nil {
				failures <- err
				return
			}
			if claim != "" {
				claims <- claim
			}
		})
	}
	workers.Wait()
	close(failures)
	close(claims)
	for err := range failures {
		t.Error(err)
	}
	unique := map[string]bool{}
	for claim := range claims {
		if unique[claim] {
			t.Errorf("queued request %s was claimed more than once", claim)
		}
		unique[claim] = true
	}
	if len(unique) != 5 {
		t.Fatalf("got %d claims, want 5", len(unique))
	}
	thread := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(thread.Messages) != 13 {
		t.Fatalf("lost replies: got %d messages", len(thread.Messages))
	}
}

// TestQueueDeduplicationCancellationAndSnapshot protects immutable work.
func TestQueueDeduplicationCancellationAndSnapshot(t *testing.T) {
	t.Parallel()
	project := t.TempDir()
	store := openStore(t, t.TempDir())
	id := create(t, store, project)
	item := run(t, store, inbox.Request{Action: "queue", Thread: id}).(inbox.Queued)
	run(t, store, inbox.Request{Action: "queue", Thread: id})
	if len(run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread).Queue) != 1 {
		t.Fatal("identical pending work duplicated")
	}
	claim := run(t, store, inbox.Request{Action: "claim", Project: project, Author: "Codex"}).(map[string]string)
	if claim["message"] != item.Message {
		t.Fatal("claim changed immutable request")
	}
	if _, err := store.Execute(t.Context(), inbox.Request{Action: "cancel", Thread: id, QueueID: item.ID, PendingOnly: true}); err == nil {
		t.Fatal("pending-only cancellation accepted claimed work")
	}
	run(t, store, inbox.Request{Action: "cancel", Thread: id, QueueID: item.ID})
	if _, err := store.Execute(t.Context(), inbox.Request{Action: "complete", Thread: id, ClaimID: claim["claim_id"]}); err == nil {
		t.Fatal("completed cancelled work")
	}
	run(t, store, inbox.Request{Action: "queue", Thread: id, Message: item.Message})
	next := run(t, store, inbox.Request{Action: "claim", Project: project, Author: "Pi"}).(map[string]string)
	run(t, store, inbox.Request{Action: "complete", Thread: id, ClaimID: next["claim_id"]})
	thread := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if thread.Resolved || thread.Queue[1].Status != "complete" {
		t.Fatal("completion should finish work without resolving conversation")
	}
}

// TestRejectedWritesPreserveStateAndRevision protects committed state.
func TestRejectedWritesPreserveStateAndRevision(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	project := t.TempDir()
	id := create(t, store, project)
	revision := run(t, store, inbox.Request{Action: "revision"}).(int64)
	for _, request := range []inbox.Request{
		{Action: "reply", Thread: id, Body: " "},
		{Action: "reply", Thread: id, Body: "hello", Author: "Agent\nspoof"},
		{Action: "resolve", Thread: id},
		{Action: "comparison", Thread: id, Label: "missing text"},
		{Action: "complete", Thread: id, ClaimID: "missing"},
		{Action: "claim", Project: project},
		{Action: "create", Project: project, Body: "Bad path", Source: &inbox.Source{Kind: "file", Path: "../escape", First: 1, Last: 1, Lines: []string{"code"}}},
	} {
		if _, err := store.Execute(t.Context(), request); err == nil {
			t.Errorf("accepted invalid action %s", request.Action)
		}
	}
	if run(t, store, inbox.Request{Action: "revision"}).(int64) != revision {
		t.Fatal("failed write changed revision")
	}
	if len(run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread).Messages) != 1 {
		t.Fatal("failed reply changed conversation")
	}
}

// TestChangePaginationAndProjectScope protects cursor coverage and scope.
func TestChangePaginationAndProjectScope(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	project := t.TempDir()
	id := create(t, store, project)
	for range 102 {
		run(t, store, inbox.Request{Action: "reply", Thread: id, Body: "More context"})
	}
	first, err := store.Changes(t.Context(), project, 0)
	if err != nil {
		t.Fatal(err)
	}
	second, err := store.Changes(t.Context(), project, first.Cursor)
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Changes) != 100 || len(second.Changes) != 3 || second.Cursor != second.Revision {
		t.Fatalf("bad cursor pages: %d and %d", len(first.Changes), len(second.Changes))
	}
	other, err := store.Changes(t.Context(), filepath.Join(project, "other"), 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(other.Changes) != 0 || other.Cursor != second.Revision {
		t.Fatal("project filtering leaked events or failed to advance cursor")
	}
}

// TestProjectCancellation checks cancellation during project discovery.
func TestProjectCancellation(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithCancel(t.Context())
	cancel()
	if _, err := inbox.Project(ctx, t.TempDir()); err == nil {
		t.Fatal("ignored cancelled context")
	}
}

func writeAndClaim(ctx context.Context, directory, project, id string, index int) (claim string, err error) {
	other, err := inbox.Open(ctx, directory)
	if err != nil {
		return "", err
	}
	defer func() { err = errors.Join(err, other.Close()) }()
	_, err = other.Execute(ctx, inbox.Request{Action: "reply", Thread: id, Author: "Agent", Body: fmt.Sprintf("Reply %d", index)})
	if err != nil {
		return "", err
	}
	result, err := other.Execute(ctx, inbox.Request{Action: "claim", Project: project, Author: "Agent"})
	if err != nil {
		return "", err
	}
	if claimed, ok := result.(map[string]string); ok {
		return claimed["queue_id"], nil
	}
	return "", nil
}

// TestOriginalCaptureSurvivesReplies verifies immutable source provenance.
func TestOriginalCaptureSurvivesReplies(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	source := inbox.Source{Kind: "file", Path: "example.go", First: 2, Last: 2, Lines: []string{"context", "original", "after"}, Modified: true, Git: map[string]string{"head": "abc123"}}
	id := run(t, store, inbox.Request{Action: "create", Project: t.TempDir(), Body: "Review this", Source: &source}).(string)
	source.Lines[1] = "changed after capture"
	before, after := "original\n", ""
	run(t, store, inbox.Request{Action: "comparison", Thread: id, Author: "Agent", Label: "Remove it", Before: &before, After: &after})
	thread := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if thread.Source.Lines[1] != "original" || thread.Source.Git["head"] != "abc123" || !thread.Source.Modified {
		t.Fatal("original capture or Git provenance changed")
	}
	if len(thread.Comparisons) != 1 || thread.Comparisons[0].After != "" || !thread.Unread {
		t.Fatal("empty replacement comparison was lost or not marked unread")
	}
}

// TestClaimsRespectProjectAndFIFO verifies project scope and FIFO.
func TestClaimsRespectProjectAndFIFO(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	project, other := t.TempDir(), t.TempDir()
	foreign := create(t, store, other)
	first := create(t, store, project)
	second := create(t, store, project)
	run(t, store, inbox.Request{Action: "queue", Thread: foreign, Message: "Foreign work"})
	run(t, store, inbox.Request{Action: "queue", Thread: second, Message: "Oldest local work"})
	run(t, store, inbox.Request{Action: "queue", Thread: first, Message: "Newest local work"})
	claim := run(t, store, inbox.Request{Action: "claim", Project: project, Author: "Worker"}).(map[string]string)
	if claim["thread"] != second || claim["message"] != "Oldest local work" {
		t.Fatalf("claimed wrong project or order: %v", claim)
	}
}

// TestMutationRollsBackIfChangeRecordFails verifies transactional rollback.
func TestMutationRollsBackIfChangeRecordFails(t *testing.T) {
	t.Parallel()
	directory := t.TempDir()
	store := openStore(t, directory)
	id := create(t, store, t.TempDir())
	db, err := sql.Open("sqlite", filepath.Join(directory, "inbox.sqlite3"))
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			t.Error(err)
		}
	}()
	_, err = db.ExecContext(t.Context(), `CREATE TRIGGER reject_change BEFORE INSERT ON changes BEGIN SELECT RAISE(ABORT,'test failure'); END`)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.Execute(t.Context(), inbox.Request{Action: "reply", Thread: id, Body: "Must roll back"}); err == nil {
		t.Fatal("expected change record failure")
	}
	thread := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(thread.Messages) != 1 {
		t.Fatal("reply committed without its notification")
	}
	revision, err := store.Revision(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	if revision != 1 {
		t.Fatalf("failed transaction advanced revision to %d", revision)
	}
}

// TestQueuedExcerptMapsSelectionToOriginalLines checks agent line provenance.
func TestQueuedExcerptMapsSelectionToOriginalLines(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	lines := make([]string, 30)
	for i := range lines {
		lines[i] = fmt.Sprintf("line %d", i+1)
	}
	source := inbox.Source{Kind: "file", Path: "example.go", First: 20, Last: 21, Lines: lines}
	id := run(t, store, inbox.Request{Action: "create", Project: t.TempDir(), Body: "Explain these lines", Source: &source}).(string)
	queued := run(t, store, inbox.Request{Action: "queue", Thread: id}).(inbox.Queued)
	_, raw, ok := strings.Cut(queued.Message, "\n{")
	if !ok {
		t.Fatal("queued request is missing structured context")
	}
	var payload struct {
		Source struct {
			First        int      `json:"first"`
			Last         int      `json:"last"`
			ExcerptFirst int      `json:"excerpt_first"`
			Lines        []string `json:"lines"`
		} `json:"source"`
	}
	if err := json.Unmarshal([]byte("{"+raw), &payload); err != nil {
		t.Fatal(err)
	}
	capture := payload.Source
	if capture.First != 20 || capture.Last != 21 || capture.ExcerptFirst < 1 || capture.First-capture.ExcerptFirst >= len(capture.Lines) {
		t.Fatalf("invalid selection coordinates: %+v", capture)
	}
	if capture.Lines[capture.First-capture.ExcerptFirst] != "line 20" {
		t.Fatal("excerpt points the agent at the wrong source line")
	}
	if len(capture.Lines) >= len(lines) {
		t.Fatal("queued request includes the entire file instead of focused context")
	}
	stored := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(stored.Source.Lines) != 30 {
		t.Fatal("excerpt extraction changed the original capture")
	}
}

// TestFinishIsAtomic prevents cancelled work from acquiring a reply or receipt.
func TestFinishIsAtomic(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	project := t.TempDir()
	id := run(t, store, inbox.Request{Action: "create", Project: project, Body: "Review this"}).(string)
	item := run(t, store, inbox.Request{Action: "queue", Thread: id}).(inbox.Queued)
	claim := run(t, store, inbox.Request{Action: "claim", Project: project, Author: "worker"}).(map[string]string)
	run(t, store, inbox.Request{Action: "cancel", Thread: id, QueueID: item.ID})
	revision := run(t, store, inbox.Request{Action: "revision"})
	if _, err := store.Execute(t.Context(), inbox.Request{Action: "finish", Thread: id, Author: "Codex", Body: "A late answer", ClaimIDs: []string{claim["claim_id"]}}); err == nil {
		t.Fatal("finished cancelled work")
	}
	thread := run(t, store, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(thread.Messages) != 1 || thread.Unread || run(t, store, inbox.Request{Action: "revision"}) != revision {
		t.Fatal("failed finish leaked a reply or change record")
	}
}

// TestConcurrentFirstOpen checks independent clients bootstrapping one inbox.
func TestConcurrentFirstOpen(t *testing.T) {
	t.Parallel()
	directory, project := t.TempDir(), t.TempDir()
	ready := make(chan struct{})
	results := make(chan error, 8)
	for i := range 8 {
		go func() {
			<-ready
			store, err := inbox.Open(t.Context(), directory)
			if err == nil {
				_, err = store.Execute(t.Context(), inbox.Request{Action: "create", Project: project, Body: fmt.Sprintf("Comment %d", i)})
				err = errors.Join(err, store.Close())
			}
			results <- err
		}()
	}
	close(ready)
	for range 8 {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	store := openStore(t, directory)
	threads := run(t, store, inbox.Request{Action: "list"}).([]inbox.Thread)
	if len(threads) != 8 {
		t.Fatalf("first-time clients lost comments: %d", len(threads))
	}
}
