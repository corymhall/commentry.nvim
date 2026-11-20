package inbox

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
)

// updatePending shares the queue writer transaction, so an edit or discard
// cannot race with publishing an immutable delivery snapshot.
func updatePending(ctx context.Context, tx *sql.Tx, thread Thread, r Request, event Event) (any, error) {
	if !thread.Pending || len(thread.Queue) != 0 || len(thread.Messages) != 1 || thread.Messages[0].Author != r.Author {
		return nil, fmt.Errorf("only your unsent pending comment can be edited or discarded")
	}
	if r.ExpectedMessage != thread.Messages[0].ID {
		return nil, fmt.Errorf("pending comment changed; refresh before editing")
	}
	if r.Action == "discard-pending" {
		if _, err := tx.ExecContext(ctx, "DELETE FROM threads WHERE id=?", thread.ID); err != nil {
			return nil, err
		}
		_, err := tx.ExecContext(ctx, "INSERT INTO changes(thread,project,inbox,kind,at) VALUES(?,?,?,?,?)", thread.ID, thread.Project, thread.Inbox, r.Action, event.At)
		return event, err
	}
	if !nonempty(r.Body) {
		return nil, fmt.Errorf("body is required")
	}
	thread.Messages[0] = Message{ID: event.ID, Author: r.Author, Body: r.Body, At: event.At}
	thread.Title = strings.Split(strings.TrimSpace(r.Body), "\n")[0]
	thread.UpdatedAt = event.At
	recordSession(&thread, r, event)
	if err := save(ctx, tx, thread, r.Action); err != nil {
		return nil, err
	}
	return event, nil
}
