package inbox

import "fmt"

func validateActor(author string, session *Session) error {
	if !label(author) {
		return fmt.Errorf("author must be a nonempty single line")
	}
	return validateSession(session)
}

func validateSession(session *Session) error {
	if session != nil && (session.Harness != "pi" || !label(session.ID) || len(session.ID) > 256) {
		return fmt.Errorf("invalid acting session")
	}
	return nil
}

func recordSession(t *Thread, r Request, e Event) {
	if r.Session == nil {
		return
	}
	// Fetch reminders do not add duplicate visits. A different session fetching
	// the same active claim remains useful evidence after a handoff.
	if r.Action == "acknowledge" {
		for _, activity := range t.SessionActivity {
			if activity.Action == r.Action && activity.ClaimID == r.ClaimID && activity.Session == *r.Session {
				return
			}
		}
	}
	t.SessionActivity = append(t.SessionActivity, SessionActivity{
		Session: *r.Session, Action: r.Action, At: e.At, EventID: e.ID,
		ClaimID: r.ClaimID, ClaimIDs: append([]string(nil), r.ClaimIDs...),
	})
}
