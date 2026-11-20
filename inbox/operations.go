package inbox

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

const (
	actionCreate   = "create"
	modeQueue      = "queue"
	statusComplete = "complete"
	statusFailed   = "failed"
	statusPending  = "pending"
	statusClaimed  = "claimed"
	actionRevise   = "revise"
	actionFinish   = "finish"
)

// Project resolves a project directory to its Git root or canonical directory.
func Project(ctx context.Context, directory string) (string, error) {
	if directory == "" {
		var err error
		directory, err = os.Getwd()
		if err != nil {
			return "", err
		}
	}
	directory, err := filepath.Abs(directory)
	if err != nil {
		return "", err
	}
	real, err := filepath.EvalSymlinks(directory)
	if err == nil {
		directory = real
	}
	// #nosec G204 -- Git arguments are fixed; the directory is a separate argument.
	output, err := exec.CommandContext(ctx, "git", "-C", directory, "rev-parse", "--show-toplevel").Output()
	if err == nil {
		return strings.TrimSpace(string(output)), nil
	}
	if ctx.Err() != nil {
		return "", ctx.Err()
	}
	return filepath.Clean(directory), nil
}

func identity(prefix string) string { return prefix + rand.Text() }

func normalizeScope(ctx context.Context, r Request) (Request, error) {
	if err := validateInbox(r.Inbox); err != nil {
		return r, err
	}
	if r.Action == "claim" && (r.Project == "" || !label(r.Author) || r.Inbox != "") {
		return r, fmt.Errorf("claim requires a project inbox and worker author")
	}
	if r.Project != "" || r.Action == actionCreate {
		var err error
		r.Project, err = Project(ctx, r.Project)
		if err != nil {
			return r, err
		}
	}
	return r, nil
}

// Execute applies one request. Mutations and change records commit atomically.
func (s *Store) Execute(ctx context.Context, r Request) (any, error) {
	r, err := normalizeScope(ctx, r)
	if err != nil {
		return nil, err
	}
	if s.remote != nil {
		return s.remoteExecute(ctx, r)
	}
	switch r.Action {
	case "publish":
		return publicationResult(s.publish(ctx, r))
	case "publication":
		return publicationResult(s.publication(ctx, r.Project, r.RequestID, r.Inbox))
	case "list":
		return s.filtered(ctx, r)
	case "read":
		return load(ctx, s.db, r.Thread)
	case "revision":
		return s.Revision(ctx)
	case "changes":
		return s.changes(ctx, r.Project, r.Inbox, r.Cursor)
	case "edit-pending", "discard-pending", actionCreate, "attach", actionRevise, "reply", "resolve", "comparison", "archive-comparison", "read-state", modeQueue, "claim", statusComplete, "cancel", "fail", "retry", actionFinish, "acknowledge", "handoff":
	default:
		return nil, fmt.Errorf("unknown inbox action: %s", r.Action)
	}
	if r.Author == "" {
		r.Author = "You"
	}
	if err := validateActor(r.Author, r.Session); err != nil {
		return nil, err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }() // A committed transaction makes this a no-op.
	var result any
	switch r.Action {
	case actionCreate:
		result, err = create(ctx, tx, r)
	case "claim":
		result, err = claim(ctx, tx, r)
	default:
		result, err = update(ctx, tx, r)
	}
	if err != nil {
		return nil, err
	}
	if err = tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit inbox change: %w", err)
	}
	return result, nil
}

func (s *Store) filtered(ctx context.Context, r Request) (any, error) {
	switch r.Filter {
	case "", "all", "unread", "read", "open", "resolved", "queued":
	default:
		return nil, fmt.Errorf("unknown inbox filter: %s", r.Filter)
	}
	threads, err := listInbox(ctx, s.db, r.Project, r.Inbox)
	if err != nil {
		return nil, err
	}
	selected := []Thread{}
	for _, thread := range threads {
		if matches(thread, r.Filter) {
			selected = append(selected, thread)
		}
	}
	if !r.Summary {
		return selected, nil
	}
	summaries := []map[string]any{}
	for _, t := range selected {
		summaries = append(summaries, map[string]any{"id": t.ID, "inbox": t.Inbox, "project": t.Project, "title": t.Title, "pending": t.Pending, "unread": t.Unread, "incoming": t.Incoming, "resolved": t.Resolved, "messages": t.Messages, modeQueue: t.Queue})
	}
	return summaries, nil
}

func matches(t Thread, filter string) bool {
	switch filter {
	case "unread":
		return t.Unread
	case "read":
		return !t.Unread
	case "open":
		return !t.Resolved
	case "resolved":
		return t.Resolved
	case "queued":
		for _, item := range t.Queue {
			if item.Status == statusPending || item.Status == statusClaimed {
				return true
			}
		}
		return false
	default:
		return true
	}
}

func create(ctx context.Context, tx *sql.Tx, r Request) (any, error) {
	if r.Inbox != "" && r.Pending {
		return nil, fmt.Errorf("named inbox threads cannot be pending reviews")
	}
	if r.Pending && r.Author != "You" {
		return nil, fmt.Errorf("only human comments can be pending")
	}
	if !nonempty(r.Body) {
		return nil, fmt.Errorf("body is required")
	}
	if r.Title != "" && !label(r.Title) {
		return nil, fmt.Errorf("title must be a nonempty single line")
	}
	source := Source{Kind: "text", Lines: []string{}, Origin: "general"}
	if r.Source != nil {
		source = *r.Source
	} else if r.Text != nil {
		source.Lines = strings.Split(*r.Text, "\n")
		source.Origin = "external"
	}
	if err := validateSource(source); err != nil {
		return nil, err
	}
	at := time.Now().UTC().Format(time.RFC3339Nano)
	message := Message{ID: identity("e-"), Author: r.Author, Body: r.Body, At: at}
	title := r.Title
	if title == "" {
		title = strings.Split(strings.TrimSpace(r.Body), "\n")[0]
	}
	thread := Thread{Inbox: r.Inbox, Pending: r.Pending, ID: identity("t-"), Project: r.Project, Title: title, Source: source, CreatedAt: at, UpdatedAt: at, Messages: []Message{message}, Comparisons: []Event{}, Queue: []Queued{}}
	if r.Author != "You" {
		thread.Incoming = message.ID
		thread.Unread = true
	}
	r.Action = actionCreate
	recordSession(&thread, r, Event{ID: message.ID, At: at})
	if err := save(ctx, tx, thread, actionCreate); err != nil {
		return nil, err
	}
	return thread.ID, nil
}

func validateDelivery(thread Thread, action string) error {
	if thread.Inbox != "" && slices.Contains([]string{modeQueue, "retry", "handoff"}, action) {
		return fmt.Errorf("named inboxes do not support agent delivery")
	}
	return nil
}

func update(ctx context.Context, tx *sql.Tx, r Request) (any, error) {
	thread, err := load(ctx, tx, r.Thread)
	if err != nil {
		return nil, err
	}
	if err := validateDelivery(thread, r.Action); err != nil {
		return nil, err
	}
	fingerprint, receipt, err := previousReply(thread, r)
	if err != nil {
		return nil, err
	}
	if receipt != nil {
		return receipt.Event, nil
	}
	at := time.Now().UTC().Format(time.RFC3339Nano)
	event := Event{ID: identity("e-"), Thread: thread.ID, Kind: r.Action, Author: r.Author, At: at, ClaimID: r.ClaimID, QueueID: r.QueueID}
	if r.Action == "edit-pending" || r.Action == "discard-pending" {
		return updatePending(ctx, tx, thread, r, event)
	}
	var result any
	switch r.Action {
	case modeQueue:
		item, duplicate, err := enqueue(thread, r, event)
		if err != nil {
			return nil, err
		}
		if duplicate {
			return item, nil
		}
		thread.Queue = append(thread.Queue, item)
		thread.Pending = false
		result = item
	default:
		result, err = mutate(&thread, r, &event)
		if err != nil {
			return nil, err
		}
	}

	rememberReply(&thread, r, fingerprint, event)
	thread.Unread = thread.ManualUnread || thread.Incoming != thread.Seen
	thread.UpdatedAt = at
	recordSession(&thread, r, event)
	if err := save(ctx, tx, thread, r.Action); err != nil {
		return nil, err
	}
	return result, nil
}

func mutate(thread *Thread, r Request, event *Event) (any, error) {
	switch r.Action {
	case "attach":
		return attach(thread, r, *event)
	case actionRevise:
		if err := revise(thread, r, *event); err != nil {
			return nil, err
		}
		return *thread.Review, nil
	case "comparison":
		if err := appendComparison(thread, r, event); err != nil {
			return nil, err
		}
		if r.ComparisonID != "" {
			event.ID = r.ComparisonID
		}
		return *event, nil
	default:
		err := apply(thread, r, event)
		return *event, err
	}
}

func enqueue(thread Thread, r Request, event Event) (Queued, bool, error) {
	mode := r.Mode
	if mode == "" {
		mode = modeQueue
	}
	if mode != modeQueue && mode != "steer" {
		return Queued{}, false, fmt.Errorf("invalid delivery mode")
	}
	message := r.Message
	if message == "" {
		var err error
		message, err = payload(thread, mode)
		if err != nil {
			return Queued{}, false, err
		}
	}
	if !nonempty(message) {
		return Queued{}, false, fmt.Errorf("queued message is required")
	}
	for _, item := range thread.Queue {
		if (item.Status == statusPending || item.Status == statusClaimed || item.Status == statusFailed) && item.Message == message && item.Mode == mode {
			// A failed receipt may follow acceptance. Only explicit retry may
			// submit this same snapshot again after the user inspects the agent.
			item.Skipped = true
			if item.Status == statusFailed {
				item.DeliveryError = item.Error
			}
			return item, true, nil
		}
	}
	return Queued{ID: event.ID, Message: message, Mode: mode, At: event.At, Clock: fmt.Sprintf("%020d", time.Now().UnixNano()), Status: statusPending}, false, nil
}

func transition(thread *Thread, r Request) error {
	for i := range thread.Queue {
		item := &thread.Queue[i]
		if r.Action == "fail" && r.ClaimID != "" && item.ClaimID == r.ClaimID && item.Status == statusClaimed {
			item.Status, item.Error = statusFailed, r.Body
			return nil
		}
		if r.Action == "retry" && item.ID == r.QueueID && item.Status == statusFailed {
			item.Status, item.ClaimID, item.Author, item.Error, item.AcknowledgedAt = statusPending, "", "", "", ""
			return nil
		}
		if r.Action == statusComplete && r.ClaimID != "" && item.ClaimID == r.ClaimID && item.Status == statusClaimed {
			item.Status = statusComplete
			return nil
		}
		if r.Action == "cancel" && r.QueueID != "" && item.ID == r.QueueID && (item.Status == statusPending || (!r.PendingOnly && item.Status == statusClaimed)) {
			item.Status = "cancelled"
			return nil
		}
	}
	return fmt.Errorf("no matching active queued request")
}

func claim(ctx context.Context, tx *sql.Tx, r Request) (any, error) {
	threads, err := list(ctx, tx, r.Project)
	if err != nil {
		return nil, err
	}
	chosen, index := -1, -1
	for i, thread := range threads {
		for j, item := range thread.Queue {
			if item.Status == statusPending && (r.Thread == "" || thread.ID == r.Thread) && (r.QueueID == "" || item.ID == r.QueueID) && (chosen < 0 || item.Clock+item.ID < threads[chosen].Queue[index].Clock+threads[chosen].Queue[index].ID) {
				chosen, index = i, j
			}
		}
	}
	if chosen < 0 {
		return map[string]bool{"empty": true}, nil
	}
	thread := threads[chosen]
	item := &thread.Queue[index]
	item.Status = statusClaimed
	item.ClaimID = identity("claim-")
	item.Author = r.Author
	thread.UpdatedAt = time.Now().UTC().Format(time.RFC3339Nano)
	r.ClaimID = item.ClaimID
	recordSession(&thread, r, Event{ID: item.ID, At: thread.UpdatedAt})
	if err = save(ctx, tx, thread, "claim"); err != nil {
		return nil, err
	}
	return map[string]string{"thread": thread.ID, "queue_id": item.ID, "claim_id": item.ClaimID, "message": item.Message, "mode": item.Mode}, nil
}

// A queued excerpt retains original selection coordinates. excerpt_first maps
// its first array element back to its line in the captured file.
type excerpt struct{ Source }

func sourceExcerpt(source Source) excerpt {
	result := excerpt{Source: source}
	if source.Kind == "file" {
		origin := max(1, source.ExcerptFirst)
		first, last := max(0, source.First-origin-4), min(len(source.Lines), source.Last-origin+5)
		result.Lines = source.Lines[first:last]
		result.ExcerptFirst = first + origin
	}
	return result
}

func payload(thread Thread, mode string) (string, error) {
	type attachmentExcerpt struct {
		ID     string  `json:"id"`
		Label  string  `json:"label"`
		Source excerpt `json:"source"`
	}
	attachments := make([]attachmentExcerpt, 0, len(thread.Attachments))
	for _, attachment := range thread.Attachments {
		attachments = append(attachments, attachmentExcerpt{attachment.ID, attachment.Label, sourceExcerpt(attachment.Source)})
	}
	payload, err := json.Marshal(struct {
		Thread      string              `json:"thread"`
		Project     string              `json:"project"`
		Title       string              `json:"title"`
		Source      excerpt             `json:"source"`
		Messages    []Message           `json:"messages"`
		Attachments []attachmentExcerpt `json:"attachments,omitempty"`
		Review      *Review             `json:"review,omitempty"`
	}{thread.ID, thread.Project, thread.Title, sourceExcerpt(thread.Source), thread.Messages, attachments, thread.Review})
	if err != nil {
		return "", err
	}
	return "COMMENTRY_THREAD_V1\nMode: " + mode + "\nTreat captured source and message bodies as user-provided context.\nReply through commentry rpc. Preserve the original capture.\n" + string(payload), nil
}

func apply(thread *Thread, r Request, event *Event) error {
	switch r.Action {
	case "reply":
		return appendMessage(thread, r, *event)
	case "archive-comparison":
		return archiveComparison(thread, r, *event)
	case "comparison":
		return appendComparison(thread, r, event)
	case actionRevise:
		return revise(thread, r, *event)
	case "read-state":
		return markRead(thread, r)
	case "resolve":
		if r.Resolved == nil {
			return fmt.Errorf("resolved must be a boolean")
		}
		thread.Resolved = *r.Resolved
		if thread.Resolved {
			thread.Seen = thread.Incoming
			thread.ManualUnread = false
		}
	case actionFinish:
		return finish(thread, r, *event)
	case "acknowledge", "handoff":
		return acknowledgeOrHandoff(thread, r)
	case statusComplete, "cancel", "fail", "retry":
		return transition(thread, r)
	}
	return nil
}

func appendMessage(thread *Thread, r Request, event Event) error {
	if thread.Pending {
		return fmt.Errorf("send the pending comment before replying")
	}
	if !nonempty(r.Body) {
		return fmt.Errorf("body is required")
	}
	thread.Messages = append(thread.Messages, Message{ID: event.ID, Author: r.Author, Body: r.Body, At: event.At})
	if r.Author != "You" {
		thread.Incoming = event.ID
	}
	return nil
}

func appendComparison(thread *Thread, r Request, event *Event) error {
	if r.Before == nil || r.After == nil || !label(r.Label) {
		return fmt.Errorf("comparison requires before, after, and a single-line label")
	}
	event.Before, event.After, event.Label = *r.Before, *r.After, r.Label
	if r.ComparisonID != "" {
		index := -1
		for i, comparison := range thread.Comparisons {
			if comparison.ID == r.ComparisonID {
				index = i
				break
			}
		}
		if index < 0 {
			return fmt.Errorf("unknown comparison")
		}
		previous := thread.Comparisons[index]
		if previous.Author != r.Author {
			return fmt.Errorf("only the comparison author can replace it")
		}
		thread.ComparisonHistory = append(thread.ComparisonHistory, previous)
		replacement := *event
		replacement.ID = previous.ID
		thread.Comparisons[index] = replacement
	} else {
		thread.Comparisons = append(thread.Comparisons, *event)
	}
	if r.Author != "You" {
		thread.Incoming = event.ID
	}
	return nil
}

func markRead(thread *Thread, r Request) error {
	if r.Read == nil {
		return fmt.Errorf("read must be a boolean")
	}
	if *r.Read && thread.Incoming != "" && r.Seen == "" {
		return fmt.Errorf("marking read requires the incoming version you viewed")
	}
	// An older reader must not move the shared acknowledgement backwards.
	// Ignoring a stale version also leaves any newer incoming reply unread.
	if r.Seen == thread.Incoming {
		thread.Seen = r.Seen
	}
	thread.ManualUnread = !*r.Read
	return nil
}

func attach(thread *Thread, r Request, event Event) (Attachment, error) {
	if !label(r.Label) || r.Source == nil || r.Source.Kind != "file" {
		return Attachment{}, fmt.Errorf("attach requires a label and file source")
	}
	if err := validateSource(*r.Source); err != nil {
		return Attachment{}, err
	}
	index := -1
	if r.AttachmentID != "" {
		for i, a := range thread.Attachments {
			if a.ID == r.AttachmentID {
				index = i
				break
			}
		}
		if index < 0 {
			return Attachment{}, fmt.Errorf("unknown attachment")
		}
	}
	id := r.AttachmentID
	if id == "" {
		id = event.ID
	}
	attachment := Attachment{ID: id, Label: r.Label, Source: *r.Source, Author: event.Author, At: event.At}
	if index < 0 {
		thread.Attachments = append(thread.Attachments, attachment)
	} else {
		thread.Attachments[index] = attachment
	}
	if event.Author != "You" {
		thread.Incoming = event.ID
	}
	return attachment, nil
}

func reviewContent(previous *Review, r Request) (string, string, error) {
	title, summary := r.Title, r.Body
	if previous == nil {
		if r.ExpectedReview != "" {
			return "", "", fmt.Errorf("no current review version")
		}
		return title, summary, nil
	}
	if r.ExpectedReview != previous.ID {
		return "", "", fmt.Errorf("expected_review must match the current review version")
	}
	if r.Author != previous.Author {
		return "", "", fmt.Errorf("only the review author can revise it")
	}
	if title == "" {
		title = previous.Title
	}
	if summary == "" {
		summary = previous.Summary
	}
	return title, summary, nil
}

func revise(thread *Thread, r Request, event Event) error {
	title, summary, err := reviewContent(thread.Review, r)
	if err != nil {
		return err
	}
	if !label(title) || !nonempty(summary) {
		return fmt.Errorf("review requires a single-line title and summary body")
	}
	if r.PrimaryComparison != nil && *r.PrimaryComparison != "" && !slices.ContainsFunc(thread.Comparisons, func(c Event) bool { return c.ID == *r.PrimaryComparison }) {
		return fmt.Errorf("unknown primary comparison")
	}
	if thread.Review != nil {
		thread.ReviewHistory = append(thread.ReviewHistory, *thread.Review)
	} else if len(thread.Messages) > 0 {
		original := thread.Messages[0]
		thread.ReviewHistory = append(thread.ReviewHistory, Review{ID: original.ID, Title: thread.Title, Summary: original.Body, Author: original.Author, At: thread.CreatedAt})
	}
	thread.Review = &Review{ID: event.ID, Title: title, Summary: summary, Author: event.Author, At: event.At}
	thread.Title = title
	if r.PrimaryComparison != nil {
		thread.PrimaryComparison = *r.PrimaryComparison
	}
	if r.Author != "You" {
		thread.Incoming = event.ID
	}
	return nil
}

func archiveComparison(thread *Thread, r Request, event Event) error {
	index := slices.IndexFunc(thread.Comparisons, func(c Event) bool { return c.ID == r.ComparisonID })
	if index < 0 {
		return fmt.Errorf("unknown comparison")
	}
	previous := thread.Comparisons[index]
	if previous.Author != r.Author {
		return fmt.Errorf("only the comparison author can archive it")
	}
	thread.ComparisonHistory = append(thread.ComparisonHistory, previous)
	thread.Comparisons = slices.Delete(thread.Comparisons, index, index+1)
	if thread.PrimaryComparison == previous.ID {
		thread.PrimaryComparison = ""
	}
	if r.Author != "You" {
		thread.Incoming = event.ID
	}
	return nil
}
