package pibridge

import (
	"encoding/json"
	"net"
	"net/http"
	"os"
	"sync/atomic"
	"testing"
	"time"
)

// TestNativeSubmissionDoesNotReplay verifies an uncertain native receipt never
// causes a retry or a second transport submission.
func TestNativeSubmissionDoesNotReplay(t *testing.T) {
	root, err := os.MkdirTemp("/tmp", "commentry-native-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(root) })
	t.Setenv("COMMENTRY_PI_RUNTIME_DIR", root)
	target := "rex/block/123"
	listener, err := net.Listen("unix", Socket(target))
	if err != nil {
		t.Fatal(err)
	}
	var count atomic.Int32
	server := &http.Server{ReadHeaderTimeout: time.Second, Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/status" {
			_ = json.NewEncoder(w).Encode(receipt{Target: target, Session: "session", Project: "/project", Directory: "/data"})
			return
		}
		var input map[string]string
		if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
			t.Error(err)
		}
		if input["session"] != "session" || input["mode"] != "queue" || input["text"] != "notification" {
			t.Errorf("bad native submission: %v", input)
		}
		count.Add(1)
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte(`{"error":"lost receipt"}`))
	})}
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(func() { _ = server.Close() })
	if err = Send(t.Context(), target, "/project", "/data", "notification", "queue"); err == nil {
		t.Fatal("accepted lost receipt")
	}
	if count.Load() != 1 {
		t.Fatalf("submitted %d times", count.Load())
	}
}
