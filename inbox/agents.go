package inbox

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
)

// Agent identifies an existing session selected for a project's deliveries.
type Agent struct {
	ID         string `json:"id"`
	Project    string `json:"project"`
	Harness    string `json:"harness"`
	Name       string `json:"name,omitempty"`
	RexSession string `json:"rex_session,omitempty"`
	RexBlock   string `json:"rex_block,omitempty"`
}

// Agent returns a project's selection, including an offline session.
func (s *Store) Agent(ctx context.Context, project string) (Agent, error) {
	if s.remote != nil {
		var a Agent
		err := s.remote.Call(ctx, "agents.get", map[string]string{"project": project}, &a)
		return a, err
	}
	var raw string
	err := s.db.QueryRowContext(ctx, "SELECT state FROM agents WHERE project=?", project).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return Agent{}, nil
	}
	if err != nil {
		return Agent{}, err
	}
	var a Agent
	err = json.Unmarshal([]byte(raw), &a)
	return a, err
}

// RegisterAgent replaces only the selection observed by its caller. Changing
// the selection never cancels work already delivered to another session.
func (s *Store) RegisterAgent(ctx context.Context, a Agent, previous string) error {
	if s.remote != nil {
		return s.remote.Call(ctx, "agents.select", map[string]any{"agent": a, "previous": previous}, nil)
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	var id string
	err = tx.QueryRowContext(ctx, "SELECT id FROM agents WHERE project=?", a.Project).Scan(&id)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if id != previous {
		return fmt.Errorf("project agent changed; inspect its status before trying again")
	}
	raw, err := json.Marshal(a)
	if err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO agents(project,id,state) VALUES(?,?,?) ON CONFLICT(project) DO UPDATE SET id=excluded.id,state=excluded.state`, a.Project, a.ID, string(raw)); err != nil {
		return err
	}
	return tx.Commit()
}

func finish(thread *Thread, r Request, event Event) error {
	if !nonempty(r.Body) || len(r.ClaimIDs) == 0 {
		return fmt.Errorf("finish requires a reply and active claim IDs")
	}
	remaining := map[string]bool{}
	for _, id := range r.ClaimIDs {
		remaining[id] = true
	}
	for i := range thread.Queue {
		q := &thread.Queue[i]
		// The agent's answer proves an uncertain delivery was accepted. A
		// retry clears the old claim ID, so superseded work still cannot finish.
		if remaining[q.ClaimID] && (q.Status == statusClaimed || q.Status == statusFailed) {
			q.Status = statusComplete
			delete(remaining, q.ClaimID)
		}
	}
	if len(remaining) > 0 {
		return fmt.Errorf("one or more claims are no longer active")
	}
	return appendMessage(thread, r, event)
}

// DetachAgent removes a selection while preserving its session and claims.
func (s *Store) DetachAgent(ctx context.Context, project, expected string) error {
	if s.remote != nil {
		return s.remote.Call(ctx, "agents.detach", map[string]string{"project": project, "expected": expected}, nil)
	}
	result, err := s.db.ExecContext(ctx, "DELETE FROM agents WHERE project=? AND id=?", project, expected)
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err == nil && n != 1 && expected != "" {
		return fmt.Errorf("project agent changed; inspect its status before trying again")
	}
	return err
}
