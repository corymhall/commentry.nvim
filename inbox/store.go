package inbox

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"github.com/corymhall/commentry.nvim/executor"
	"modernc.org/sqlite" // Registers the pure-Go SQLite driver.
)

// Store routes inbox operations to Executor, or owns a legacy SQLite pool.
// Call Close when its caller finishes.
type Store struct {
	db     *sql.DB
	remote *executor.Client
}

// DefaultDirectory matches Neovim's default data directory on Unix systems.
func DefaultDirectory() (string, error) {
	if directory := os.Getenv("COMMENTRY_INBOX_DIR"); directory != "" {
		return directory, nil
	}
	base := os.Getenv("XDG_DATA_HOME")
	if base == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		base = filepath.Join(home, ".local", "share")
	}
	app := os.Getenv("NVIM_APPNAME")
	if app == "" {
		app = "nvim"
	}
	return filepath.Join(base, app, "commentry", "inbox"), nil
}

// Open selects the configured Executor app or an unconfigured legacy inbox.
func Open(ctx context.Context, directory string) (*Store, error) {
	if directory == "" {
		var err error
		directory, err = DefaultDirectory()
		if err != nil {
			return nil, err
		}
	}
	directory, err := filepath.Abs(directory)
	if err != nil {
		return nil, err
	}
	remote, err := executor.Open(directory)
	if err == nil {
		return &Store{remote: remote}, nil
	}
	if !executor.IsUnconfigured(err) {
		return nil, err
	}
	// Unconfigured directories retain the legacy store for explicit migration
	// and isolated offline tests. A configured Executor never falls back here.
	if err = os.MkdirAll(directory, 0o700); err != nil {
		return nil, fmt.Errorf("create inbox directory: %w", err)
	}
	filename := filepath.Join(directory, "inbox.sqlite3")
	// #nosec G304 -- The caller explicitly selects the local data directory.
	file, err := os.OpenFile(filename, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err = file.Close(); err != nil {
		return nil, err
	}
	uri := url.URL{Scheme: "file", Path: filename}
	// Reserve the writer before loading thread state. This keeps read/modify/write
	// operations and competing queue claims atomic across independent processes.
	query := url.Values{"_pragma": {"busy_timeout(5000)", "journal_mode(WAL)", "synchronous(FULL)"}, "_txlock": {"immediate"}}
	uri.RawQuery = query.Encode()
	db, err := sql.Open("sqlite", uri.String())
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	store := &Store{db: db}
	if err = store.initializeWaiting(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("open inbox: %w", err)
	}
	return store, nil
}

func (s *Store) initialize(ctx context.Context) error {
	const currentVersion = 4
	var version int
	if err := s.db.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	if version == currentVersion {
		return nil
	}
	if version > currentVersion {
		return fmt.Errorf("unsupported inbox database version %d", version)
	}
	// Recheck under the writer lock so concurrent initializers cannot apply
	// the same migration twice. Normal opens need no writer reservation.
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if err = tx.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	if version > currentVersion {
		return fmt.Errorf("unsupported inbox database version %d", version)
	}
	if version < 3 {
		if _, err = tx.ExecContext(ctx, ` CREATE TABLE IF NOT EXISTS threads (
 position INTEGER PRIMARY KEY AUTOINCREMENT,
 id TEXT NOT NULL UNIQUE,
 project TEXT NOT NULL,
 state TEXT NOT NULL CHECK(json_valid(state))
 );
 CREATE INDEX IF NOT EXISTS threads_project ON threads(project,position);
 CREATE TABLE IF NOT EXISTS changes (
 sequence INTEGER PRIMARY KEY AUTOINCREMENT,
 thread TEXT NOT NULL,
 project TEXT NOT NULL,
 kind TEXT NOT NULL,
 at TEXT NOT NULL
 );
 CREATE INDEX IF NOT EXISTS changes_project ON changes(project,sequence);
 CREATE TABLE IF NOT EXISTS agents (
 project TEXT PRIMARY KEY,
 id TEXT NOT NULL,
 state TEXT NOT NULL CHECK(json_valid(state))
 );
 CREATE TABLE IF NOT EXISTS publications (
 project TEXT NOT NULL,
 request_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL,
 receipt TEXT NOT NULL CHECK(json_valid(receipt)),
 PRIMARY KEY(project,request_id)
 );
`); err != nil {
			return err
		}
	}
	if version < 4 {
		if _, err = tx.ExecContext(ctx, `ALTER TABLE threads ADD COLUMN inbox TEXT NOT NULL DEFAULT '';
CREATE INDEX threads_inbox ON threads(inbox,position);
ALTER TABLE changes ADD COLUMN inbox TEXT NOT NULL DEFAULT '';
CREATE INDEX changes_inbox ON changes(inbox,sequence);
ALTER TABLE publications RENAME TO publications_previous;
CREATE TABLE publications (
 inbox TEXT NOT NULL DEFAULT '', project TEXT NOT NULL, request_id TEXT NOT NULL,
 fingerprint TEXT NOT NULL, receipt TEXT NOT NULL CHECK(json_valid(receipt)),
 PRIMARY KEY(inbox,project,request_id)
);
INSERT INTO publications(project,request_id,fingerprint,receipt)
 SELECT project,request_id,fingerprint,receipt FROM publications_previous;
DROP TABLE publications_previous;
PRAGMA user_version=4;`); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// Close releases database resources.
func (s *Store) Close() error {
	if s.remote != nil {
		return nil
	}
	return s.db.Close()
}

// Revision returns the latest committed change sequence.
func (s *Store) Revision(ctx context.Context) (int64, error) {
	var revision int64
	if s.remote != nil {
		err := s.remote.Call(ctx, "revision", struct{}{}, &revision)
		return revision, err
	}
	err := s.db.QueryRowContext(ctx, "SELECT COALESCE(MAX(sequence),0) FROM changes").Scan(&revision)
	return revision, err
}

// Changes returns at most 100 changes through a stable revision boundary.
func (s *Store) Changes(ctx context.Context, project string, cursor int64) (Changes, error) {
	return s.changes(ctx, project, "", cursor)
}

func (s *Store) changes(ctx context.Context, project, inbox string, cursor int64) (Changes, error) {
	result := Changes{Changes: []Change{}, Cursor: cursor}
	if project != "" {
		var err error
		project, err = Project(ctx, project)
		if err != nil {
			return result, err
		}
	}
	if cursor < 0 {
		return result, fmt.Errorf("cursor cannot be negative")
	}
	if s.remote != nil {
		input := map[string]any{"project": project, "cursor": cursor}
		if inbox != "" {
			input["inbox"] = inbox
		}
		err := s.remote.Call(ctx, "changes", input, &result)
		return result, err
	}
	// Bound the page before querying, so a concurrent commit cannot be skipped
	// when advancing the cursor past changes from unrelated projects.
	revision, err := s.Revision(ctx)
	if err != nil {
		return result, err
	}
	result.Revision = revision
	rows, err := s.db.QueryContext(ctx, `SELECT sequence,thread,project,inbox,kind,at FROM changes
 WHERE sequence>? AND sequence<=? AND (?='' OR project=?) AND (inbox=? OR (?='' AND ?='')) ORDER BY sequence LIMIT 100`, cursor, revision, project, project, inbox, inbox, project)
	if err != nil {
		return result, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var change Change
		if err = rows.Scan(&change.Sequence, &change.Thread, &change.Project, &change.Inbox, &change.Kind, &change.At); err != nil {
			return result, err
		}
		result.Changes = append(result.Changes, change)
		result.Cursor = change.Sequence
	}
	if err = rows.Err(); err != nil {
		return result, err
	}
	if len(result.Changes) < 100 && cursor < revision {
		result.Cursor = revision
	}
	return result, nil
}

type queryer interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func load(ctx context.Context, db queryer, id string) (Thread, error) {
	var raw string
	err := db.QueryRowContext(ctx, "SELECT state FROM threads WHERE id=?", id).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return Thread{}, fmt.Errorf("unknown inbox thread: %s", id)
	}
	if err != nil {
		return Thread{}, err
	}
	var thread Thread
	if err = json.Unmarshal([]byte(raw), &thread); err != nil {
		return thread, fmt.Errorf("invalid stored thread %s: %w", id, err)
	}
	return thread, nil
}

func list(ctx context.Context, db queryer, project string) ([]Thread, error) {
	return listInbox(ctx, db, project, "")
}

func listInbox(ctx context.Context, db queryer, project, inbox string) ([]Thread, error) {
	rows, err := db.QueryContext(ctx, "SELECT state FROM threads WHERE (?='' OR project=?) AND (inbox=? OR (?='' AND ?='')) ORDER BY position", project, project, inbox, inbox, project)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	threads := []Thread{}
	for rows.Next() {
		var raw string
		if err = rows.Scan(&raw); err != nil {
			return nil, err
		}
		var thread Thread
		if err = json.Unmarshal([]byte(raw), &thread); err != nil {
			return nil, fmt.Errorf("invalid stored thread: %w", err)
		}
		threads = append(threads, thread)
	}
	return threads, rows.Err()
}

func save(ctx context.Context, tx *sql.Tx, thread Thread, kind string) error {
	raw, err := json.Marshal(thread)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO threads(id,project,inbox,state) VALUES(?,?,?,?)
 ON CONFLICT(id) DO UPDATE SET state=excluded.state`, thread.ID, thread.Project, thread.Inbox, string(raw))
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO changes(thread,project,inbox,kind,at) VALUES(?,?,?,?,?)", thread.ID, thread.Project, thread.Inbox, kind, time.Now().UTC().Format(time.RFC3339Nano))
	return err
}

// Independent first-time readers can race the WAL transition before any
// schema exists. Retry only SQLite contention, using a bounded startup budget.
func (s *Store) initializeWaiting(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	for {
		err := s.initialize(ctx)
		var issue *sqlite.Error
		if !errors.As(err, &issue) || (issue.Code()&0xff != 5 && issue.Code()&0xff != 6) {
			return err
		}
		select {
		case <-ctx.Done():
			return errors.Join(err, ctx.Err())
		case <-time.After(25 * time.Millisecond):
		}
	}
}
