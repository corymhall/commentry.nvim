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

	_ "modernc.org/sqlite" // Registers the pure-Go SQLite driver.
)

// Store owns a SQLite connection pool. Call Close when its caller finishes.
type Store struct{ db *sql.DB }

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

// Open creates or opens the inbox, with WAL and bounded writer contention.
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
	if err = store.initialize(ctx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("open inbox: %w", err)
	}
	return store, nil
}

func (s *Store) initialize(ctx context.Context) error {
	var version int
	if err := s.db.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	if version > 1 {
		return fmt.Errorf("unsupported inbox database version %d", version)
	}
	if version == 1 {
		return nil
	}
	_, err := s.db.ExecContext(ctx, `BEGIN IMMEDIATE;
 CREATE TABLE IF NOT EXISTS threads (
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
 PRAGMA user_version=1;
 COMMIT;`)
	return err
}

// Close releases database resources.
func (s *Store) Close() error { return s.db.Close() }

// Revision returns the latest committed change sequence.
func (s *Store) Revision(ctx context.Context) (int64, error) {
	var revision int64
	err := s.db.QueryRowContext(ctx, "SELECT COALESCE(MAX(sequence),0) FROM changes").Scan(&revision)
	return revision, err
}

// Changes returns at most 100 changes through a stable revision boundary.
func (s *Store) Changes(ctx context.Context, project string, cursor int64) (Changes, error) {
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
	// Bound the page before querying, so a concurrent commit cannot be skipped
	// when advancing the cursor past changes from unrelated projects.
	revision, err := s.Revision(ctx)
	if err != nil {
		return result, err
	}
	result.Revision = revision
	rows, err := s.db.QueryContext(ctx, `SELECT sequence,thread,project,kind,at FROM changes
 WHERE sequence>? AND sequence<=? AND (?='' OR project=?) ORDER BY sequence LIMIT 100`, cursor, revision, project, project)
	if err != nil {
		return result, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var change Change
		if err = rows.Scan(&change.Sequence, &change.Thread, &change.Project, &change.Kind, &change.At); err != nil {
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
	rows, err := db.QueryContext(ctx, "SELECT state FROM threads WHERE (?='' OR project=?) ORDER BY position", project, project)
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
	_, err = tx.ExecContext(ctx, `INSERT INTO threads(id,project,state) VALUES(?,?,?)
 ON CONFLICT(id) DO UPDATE SET state=excluded.state`, thread.ID, thread.Project, string(raw))
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, "INSERT INTO changes(thread,project,kind,at) VALUES(?,?,?,?)", thread.ID, thread.Project, kind, time.Now().UTC().Format(time.RFC3339Nano))
	return err
}
