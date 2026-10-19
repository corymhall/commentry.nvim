// Package inbox owns persistent project conversations and queued agent work.
package inbox

import (
	"fmt"
	"path"
	"slices"
	"strings"
)

// Source is the immutable text or file snapshot captured with a thread.
type Source struct {
	Kind     string            `json:"kind"`
	Lines    []string          `json:"lines"`
	Path     string            `json:"path,omitempty"`
	First    int               `json:"first,omitempty"`
	Last     int               `json:"last,omitempty"`
	Origin   string            `json:"origin,omitempty"`
	Filetype string            `json:"filetype,omitempty"`
	Modified bool              `json:"modified,omitempty"`
	Git      map[string]string `json:"git,omitempty"`
}

// Attachment is a named code snapshot independent of the original capture.
type Attachment struct {
	ID     string `json:"id"`
	Label  string `json:"label"`
	Source Source `json:"source"`
	Author string `json:"author"`
	At     string `json:"at"`
}

// Message is a single contribution to a conversation.
type Message struct {
	ID     string `json:"id"`
	Author string `json:"author"`
	Body   string `json:"body"`
	At     string `json:"at"`
}

// Event is a mutation receipt. Comparison receipts are retained on the thread.
type Event struct {
	ID      string `json:"id"`
	Thread  string `json:"thread"`
	Kind    string `json:"kind"`
	Author  string `json:"author"`
	At      string `json:"at"`
	Before  string `json:"before"`
	After   string `json:"after"`
	Label   string `json:"label,omitempty"`
	ClaimID string `json:"claim_id,omitempty"`
	QueueID string `json:"queue_id,omitempty"`
}

// Queued retains an immutable request body alongside its delivery state.
// Skipped and DeliveryError describe one CLI attempt and are not persisted.
type Queued struct {
	Skipped       bool   `json:"skipped,omitempty"`
	DeliveryError string `json:"delivery_error,omitempty"`
	Error         string `json:"error,omitempty"`
	ID            string `json:"id"`
	Message       string `json:"message"`
	Mode          string `json:"mode"`
	At            string `json:"at"`
	Clock         string `json:"clock"`
	Status        string `json:"status"`
	ClaimID       string `json:"claim_id,omitempty"`
	Author        string `json:"author,omitempty"`
}

// Thread contains a capture, conversation, comparisons, and read/work state.
type Thread struct {
	ID           string       `json:"id"`
	Project      string       `json:"project"`
	Title        string       `json:"title"`
	Source       Source       `json:"source"`
	Attachments  []Attachment `json:"attachments,omitempty"`
	CreatedAt    string       `json:"created_at"`
	UpdatedAt    string       `json:"updated_at"`
	Resolved     bool         `json:"resolved"`
	Messages     []Message    `json:"messages"`
	Comparisons  []Event      `json:"comparisons"`
	Queue        []Queued     `json:"queue"`
	Unread       bool         `json:"unread"`
	Incoming     string       `json:"incoming,omitempty"`
	Seen         string       `json:"seen,omitempty"`
	ManualUnread bool         `json:"manual_unread"`
}

// Request is the shared CLI and Neovim JSON protocol.
type Request struct {
	Action        string   `json:"action"`
	DeferDelivery bool     `json:"defer_delivery,omitempty"`
	AttachmentID  string   `json:"attachment_id,omitempty"`
	Mode          string   `json:"mode,omitempty"`
	ClaimIDs      []string `json:"claim_ids,omitempty"`
	Thread        string   `json:"thread,omitempty"`
	Project       string   `json:"project,omitempty"`
	Author        string   `json:"author,omitempty"`
	Title         string   `json:"title,omitempty"`
	Body          string   `json:"body,omitempty"`
	Text          *string  `json:"text,omitempty"`
	Source        *Source  `json:"source,omitempty"`
	Filter        string   `json:"filter,omitempty"`
	Summary       bool     `json:"summary,omitempty"`
	Resolved      *bool    `json:"resolved,omitempty"`
	Read          *bool    `json:"read,omitempty"`
	Seen          string   `json:"seen,omitempty"`
	Before        *string  `json:"before,omitempty"`
	After         *string  `json:"after,omitempty"`
	Label         string   `json:"label,omitempty"`
	Message       string   `json:"message,omitempty"`
	ClaimID       string   `json:"claim_id,omitempty"`
	QueueID       string   `json:"queue_id,omitempty"`
	PendingOnly   bool     `json:"pending_only,omitempty"`
	Cursor        int64    `json:"cursor,omitempty"`
}

// Change identifies a committed mutation for incremental inbox consumers.
type Change struct {
	Sequence int64  `json:"sequence"`
	Thread   string `json:"thread"`
	Project  string `json:"project"`
	Kind     string `json:"kind"`
	At       string `json:"at"`
}

// Changes is a bounded page with a resumable cursor.
type Changes struct {
	Changes  []Change `json:"changes"`
	Cursor   int64    `json:"cursor"`
	Revision int64    `json:"revision"`
}

func nonempty(s string) bool { return strings.TrimSpace(s) != "" }
func label(s string) bool    { return nonempty(s) && !strings.ContainsAny(s, "\r\n") }

func validateSource(s Source) error {
	if s.Lines == nil {
		return fmt.Errorf("source.lines must be an array")
	}
	for _, line := range s.Lines {
		if strings.Contains(line, "\n") {
			return fmt.Errorf("source lines cannot contain newlines")
		}
	}
	if s.Kind == "text" {
		return nil
	}
	if s.Kind != "file" || !nonempty(s.Path) || path.IsAbs(s.Path) || strings.ContainsAny(s.Path, "\\:\r\n") {
		return fmt.Errorf("invalid relative source path")
	}
	if slices.Contains(strings.Split(s.Path, "/"), "..") {
		return fmt.Errorf("source path cannot escape project")
	}
	if s.First < 1 || s.Last < s.First || s.Last > len(s.Lines) {
		return fmt.Errorf("invalid source range")
	}
	return validateMetadata(s)
}

func validateMetadata(s Source) error {
	if strings.ContainsAny(s.Filetype, "\r\n") {
		return fmt.Errorf("invalid filetype")
	}
	for _, value := range s.Git {
		if strings.ContainsAny(value, "\r\n") {
			return fmt.Errorf("invalid git metadata")
		}
	}
	return nil
}
