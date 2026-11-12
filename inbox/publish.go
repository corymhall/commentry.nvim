package inbox

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
)

// PublishItem is one independently reviewable topic and its evidence.
type PublishItem struct {
	Key               string              `json:"key"`
	Title             string              `json:"title"`
	Body              string              `json:"body"`
	Source            *Source             `json:"source,omitempty"`
	Attachments       []PublishAttachment `json:"attachments,omitempty"`
	Comparisons       []PublishComparison `json:"comparisons,omitempty"`
	PrimaryComparison string              `json:"primary_comparison,omitempty"`
}

// PublishAttachment carries a named file snapshot or explicit excerpt.
type PublishAttachment struct {
	Label  string `json:"label"`
	Source Source `json:"source"`
}

// PublishComparison pairs versions of the same material within a topic.
type PublishComparison struct {
	Key    string `json:"key"`
	Label  string `json:"label"`
	Before string `json:"before"`
	After  string `json:"after"`
}

// EvidenceReceipt names saved evidence without echoing its source text.
type EvidenceReceipt struct {
	ID    string `json:"id"`
	Key   string `json:"key,omitempty"`
	Label string `json:"label"`
}

// PublishedItem maps a caller's topic key to the atomically saved conversation.
type PublishedItem struct {
	Key               string            `json:"key"`
	Thread            string            `json:"thread"`
	Title             string            `json:"title"`
	Review            string            `json:"review"`
	Attachments       []EvidenceReceipt `json:"attachments"`
	Comparisons       []EvidenceReceipt `json:"comparisons"`
	PrimaryComparison string            `json:"primary_comparison,omitempty"`
}

// PublishReceipt is durable even if the caller loses the original response.
type PublishReceipt struct {
	Project   string          `json:"project"`
	RequestID string          `json:"request_id"`
	Status    string          `json:"status"`
	Items     []PublishedItem `json:"items,omitempty"`
}

func publicationResult(receipt PublishReceipt, err error) (any, error) {
	if err != nil {
		return nil, err
	}
	return receipt, nil
}

func publicationIdentity(project, requestID string) error {
	if !label(project) || !label(requestID) || len(requestID) > 200 {
		return fmt.Errorf("project and request_id are required; request_id must be a single line of at most 200 characters")
	}
	return nil
}

func (s *Store) publication(ctx context.Context, project, requestID string) (PublishReceipt, error) {
	result := PublishReceipt{Project: project, RequestID: requestID, Status: "missing"}
	if err := publicationIdentity(project, requestID); err != nil {
		return result, err
	}
	var raw string
	err := s.db.QueryRowContext(ctx, "SELECT receipt FROM publications WHERE project=? AND request_id=?", project, requestID).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return result, nil
	}
	if err != nil {
		return result, err
	}
	err = json.Unmarshal([]byte(raw), &result)
	return result, err
}

func validatePublication(r Request) error {
	if err := publicationIdentity(r.Project, r.RequestID); err != nil {
		return err
	}
	if err := validateActor(r.Author, r.Session); err != nil {
		return err
	}
	if len(r.Items) < 1 || len(r.Items) > 25 {
		return fmt.Errorf("publish requires 1 to 25 topics")
	}
	keys := map[string]bool{}
	for _, item := range r.Items {
		if !label(item.Key) || keys[item.Key] {
			return fmt.Errorf("topic keys must be nonempty and unique")
		}
		keys[item.Key] = true
		if err := validatePublishItem(item); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) publish(ctx context.Context, r Request) (PublishReceipt, error) {
	receipt := PublishReceipt{Project: r.Project, RequestID: r.RequestID, Status: "complete", Items: []PublishedItem{}}
	if err := validatePublication(r); err != nil {
		return receipt, err
	}
	data, err := json.Marshal(struct {
		Project   string
		RequestID string
		Author    string
		Items     []PublishItem
	}{r.Project, r.RequestID, r.Author, r.Items})
	if err != nil {
		return receipt, err
	}
	sum := sha256.Sum256(data)
	fingerprint := hex.EncodeToString(sum[:])
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return receipt, err
	}
	defer func() { _ = tx.Rollback() }()
	var priorHash, raw string
	err = tx.QueryRowContext(ctx, "SELECT fingerprint,receipt FROM publications WHERE project=? AND request_id=?", r.Project, r.RequestID).Scan(&priorHash, &raw)
	if err == nil {
		if priorHash != fingerprint {
			return receipt, fmt.Errorf("request_id already used with different content; inspect publication or use a new request_id")
		}
		err = json.Unmarshal([]byte(raw), &receipt)
		return receipt, err
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return receipt, err
	}
	for _, item := range r.Items {
		saved, saveErr := publishItem(ctx, tx, r, item)
		if saveErr != nil {
			return receipt, saveErr
		}
		receipt.Items = append(receipt.Items, saved)
	}
	data, err = json.Marshal(receipt)
	if err != nil {
		return receipt, err
	}
	if _, err = tx.ExecContext(ctx, "INSERT INTO publications(project,request_id,fingerprint,receipt) VALUES(?,?,?,?)", r.Project, r.RequestID, fingerprint, string(data)); err != nil {
		return receipt, err
	}
	err = tx.Commit()
	return receipt, err
}

func publishItem(ctx context.Context, tx *sql.Tx, r Request, item PublishItem) (PublishedItem, error) {
	result := PublishedItem{Key: item.Key, Title: item.Title, Attachments: []EvidenceReceipt{}, Comparisons: []EvidenceReceipt{}}
	value, err := create(ctx, tx, Request{Project: r.Project, Author: r.Author, Title: item.Title, Body: item.Body, Source: item.Source, Session: r.Session})
	if err != nil {
		return result, err
	}
	result.Thread = value.(string)
	base := Request{Project: r.Project, Author: r.Author, Thread: result.Thread, Session: r.Session}
	for _, a := range item.Attachments {
		req := base
		req.Action = "attach"
		req.Label = a.Label
		req.Source = &a.Source
		value, err = update(ctx, tx, req)
		if err != nil {
			return result, err
		}
		saved := value.(Attachment)
		result.Attachments = append(result.Attachments, EvidenceReceipt{ID: saved.ID, Label: saved.Label})
	}
	for _, c := range item.Comparisons {
		req := base
		req.Action = "comparison"
		req.Label = c.Label
		req.Before = &c.Before
		req.After = &c.After
		value, err = update(ctx, tx, req)
		if err != nil {
			return result, err
		}
		saved := value.(Event)
		result.Comparisons = append(result.Comparisons, EvidenceReceipt{ID: saved.ID, Key: c.Key, Label: saved.Label})
		if c.Key == item.PrimaryComparison {
			result.PrimaryComparison = saved.ID
		}
	}
	base.Action = actionRevise
	base.Title = item.Title
	base.Body = item.Body
	if result.PrimaryComparison != "" {
		base.PrimaryComparison = &result.PrimaryComparison
	}
	value, err = update(ctx, tx, base)
	if err != nil {
		return result, err
	}
	result.Review = value.(Review).ID
	return result, nil
}

func validatePublishItem(item PublishItem) error {
	if !label(item.Title) || !nonempty(item.Body) {
		return fmt.Errorf("each topic requires a title and body")
	}
	comparisons := map[string]bool{}
	for _, c := range item.Comparisons {
		if !label(c.Key) || comparisons[c.Key] {
			return fmt.Errorf("comparison keys must be nonempty and unique within a topic")
		}
		comparisons[c.Key] = true
	}
	if item.PrimaryComparison != "" && !comparisons[item.PrimaryComparison] {
		return fmt.Errorf("primary_comparison must name a comparison key in its topic")
	}
	return nil
}
