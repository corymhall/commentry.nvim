package inbox

import (
	"encoding/json"
	"fmt"
	"slices"
	"time"
)

func previousReply(t Thread, r Request) (string, *ReplyReceipt, error) {
	fingerprint, err := replyFingerprint(r)
	if err != nil {
		return "", nil, err
	}
	if fingerprint == "" {
		return "", nil, nil
	}
	receipt, ok := t.ReplyReceipts[r.RequestID]
	if !ok {
		return fingerprint, nil, nil
	}
	// Receipts survive legacy export/import. Normalize JSON escaping because
	// Go and JavaScript encode HTML characters differently.
	var saved any
	if err := json.Unmarshal([]byte(receipt.Fingerprint), &saved); err != nil {
		return "", nil, fmt.Errorf("invalid saved reply receipt: %w", err)
	}
	normalized, err := json.Marshal(saved)
	if err != nil {
		return "", nil, err
	}
	if string(normalized) != fingerprint {
		return "", nil, fmt.Errorf("request_id already used with different reply")
	}
	return fingerprint, &receipt, nil
}

func rememberReply(t *Thread, r Request, fingerprint string, e Event) {
	if fingerprint == "" {
		return
	}
	if t.ReplyReceipts == nil {
		t.ReplyReceipts = map[string]ReplyReceipt{}
	}
	t.ReplyReceipts[r.RequestID] = ReplyReceipt{Fingerprint: fingerprint, Event: e}
}

func acknowledgeOrHandoff(t *Thread, r Request) error {
	index := slices.IndexFunc(t.Queue, func(q Queued) bool {
		return r.ClaimID != "" && q.ClaimID == r.ClaimID && (q.Status == statusClaimed || q.Status == statusFailed)
	})
	if index < 0 {
		return fmt.Errorf("no matching active queued request")
	}
	q := &t.Queue[index]
	if r.Action == "acknowledge" {
		if q.AcknowledgedAt == "" {
			q.AcknowledgedAt = time.Now().UTC().Format(time.RFC3339Nano)
		}
		return nil
	}
	if q.ID != r.QueueID {
		return fmt.Errorf("no matching active queued request")
	}
	q.Status, q.ClaimID, q.Author, q.Error, q.AcknowledgedAt = statusPending, "", "", "", ""
	return nil
}

func replyFingerprint(r Request) (string, error) {
	if r.RequestID == "" || (r.Action != "reply" && r.Action != actionFinish) {
		return "", nil
	}
	if !label(r.RequestID) || len(r.RequestID) > 200 {
		return "", fmt.Errorf("invalid request_id")
	}
	claims := append([]string{}, r.ClaimIDs...)
	slices.Sort(claims)
	raw, err := json.Marshal([]any{r.Action, r.Author, r.Body, claims})
	return string(raw), err
}
