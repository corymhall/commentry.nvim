package inbox

import (
	"context"
	"encoding/json"
)

func decodeRemote[T any](raw json.RawMessage) (any, error) {
	var result T
	err := json.Unmarshal(raw, &result)
	return result, err
}

// Preserve the local CLI's response types while Executor owns the operation.
func (s *Store) remoteExecute(ctx context.Context, r Request) (any, error) {
	var raw json.RawMessage
	if err := s.remote.Call(ctx, "rpc", r, &raw); err != nil {
		return nil, err
	}
	switch r.Action {
	case "list":
		if r.Summary {
			return decodeRemote[[]map[string]any](raw)
		}
		return decodeRemote[[]Thread](raw)
	case "read":
		return decodeRemote[Thread](raw)
	case "create":
		return decodeRemote[string](raw)
	case "attach":
		return decodeRemote[Attachment](raw)
	case "queue":
		return decodeRemote[Queued](raw)
	case "revision":
		return decodeRemote[int64](raw)
	case "changes":
		return decodeRemote[Changes](raw)
	case "claim":
		var empty struct {
			Empty bool `json:"empty"`
		}
		if err := json.Unmarshal(raw, &empty); err != nil {
			return nil, err
		}
		if empty.Empty {
			return map[string]bool{"empty": true}, nil
		}
		return decodeRemote[map[string]string](raw)
	default:
		return decodeRemote[Event](raw)
	}
}
