package inbox_test

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// TestNamedInboxMigrationPreservesPublicationRetry keeps old receipts usable.
func TestNamedInboxMigrationPreservesPublicationRetry(t *testing.T) {
	t.Parallel()
	directory, project := t.TempDir(), t.TempDir()
	canonical, err := inbox.Project(t.Context(), project)
	if err != nil {
		t.Fatal(err)
	}
	request := inbox.Request{Action: "publish", Project: canonical, RequestID: "legacy-review", Author: "pi", Items: []inbox.PublishItem{{Key: "old", Title: "Existing topic", Body: "Original capture"}}}
	oldContent, err := json.Marshal(struct {
		Project   string
		RequestID string
		Author    string
		Items     []inbox.PublishItem
	}{request.Project, request.RequestID, request.Author, request.Items})
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(oldContent)
	receipt := inbox.PublishReceipt{Project: canonical, RequestID: request.RequestID, Status: "complete", Items: []inbox.PublishedItem{{Key: "old", Thread: "t-original"}}}
	raw, err := json.Marshal(receipt)
	if err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite", filepath.Join(directory, "inbox.sqlite3"))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = db.Close() }()
	for _, filename := range []string{"0001_inbox.sql", "0002_publications.sql"} {
		// #nosec G304 -- Both migration filenames are fixed test fixtures above.
		migration, readErr := os.ReadFile(filepath.Join("..", "integrations", "executor", "migrations", filename))
		if readErr != nil {
			t.Fatal(readErr)
		}
		if _, err = db.ExecContext(t.Context(), string(migration)); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = db.ExecContext(t.Context(), "PRAGMA user_version=3"); err != nil {
		t.Fatal(err)
	}
	if _, err = db.ExecContext(t.Context(), "INSERT INTO publications(project,request_id,fingerprint,receipt) VALUES(?,?,?,?)", canonical, request.RequestID, hex.EncodeToString(sum[:]), string(raw)); err != nil {
		t.Fatal(err)
	}
	store := openStore(t, directory)
	saved := run(t, store, request).(inbox.PublishReceipt)
	if len(saved.Items) != 1 || saved.Items[0].Thread != "t-original" {
		t.Fatalf("migration lost legacy retry receipt: %+v", saved)
	}
	if threads := run(t, store, inbox.Request{Action: "list"}).([]inbox.Thread); len(threads) != 0 {
		t.Fatalf("retry created duplicate threads: %+v", threads)
	}
}

// TestNamedInboxOriginsAndDeliveryIsolation checks routing and origin metadata.
func TestNamedInboxOriginsAndDeliveryIsolation(t *testing.T) {
	t.Parallel()
	store := openStore(t, t.TempDir())
	one, two := t.TempDir(), t.TempDir()
	ordinary := create(t, store, one)
	var ids []string
	for _, project := range []string{one, two} {
		ids = append(ids, run(t, store, inbox.Request{Action: "create", Inbox: "agent-friction", Project: project, Author: "pi", Body: "Slow discovery"}).(string))
	}
	shared := run(t, store, inbox.Request{Action: "list", Inbox: "agent-friction"}).([]inbox.Thread)
	if len(shared) != 2 || shared[0].Project == shared[1].Project {
		t.Fatalf("lost shared origins: %+v", shared)
	}
	project := run(t, store, inbox.Request{Action: "list", Project: one}).([]inbox.Thread)
	if len(project) != 1 || project[0].ID != ordinary {
		t.Fatalf("project scope leaked: %+v", project)
	}
	changes := run(t, store, inbox.Request{Action: "changes", Inbox: "agent-friction"}).(inbox.Changes)
	if len(changes.Changes) != 2 || changes.Changes[1].Inbox != "agent-friction" {
		t.Fatalf("wrong change scope: %+v", changes)
	}
	if _, err := store.Execute(t.Context(), inbox.Request{Action: "queue", Thread: ids[0]}); err == nil {
		t.Fatal("shared thread entered project delivery queue")
	}
	request := inbox.Request{Action: "publish", Inbox: "agent-friction", Project: one, Author: "pi", RequestID: "feedback-1", Items: []inbox.PublishItem{{Key: "friction", Title: "Slow discovery", Body: "Discovery took five calls."}}}
	saved := run(t, store, request).(inbox.PublishReceipt)
	retry := run(t, store, request).(inbox.PublishReceipt)
	if saved.Items[0].Thread != retry.Items[0].Thread || saved.Inbox != request.Inbox {
		t.Fatal("publication retry lost identity")
	}
	request.Inbox = "ideas"
	other := run(t, store, request).(inbox.PublishReceipt)
	if other.Items[0].Thread == saved.Items[0].Thread {
		t.Fatal("publication identity crossed inboxes")
	}
}
