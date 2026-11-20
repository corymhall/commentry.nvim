package pibridge

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/corymhall/commentry.nvim/executor"
	"github.com/corymhall/commentry.nvim/inbox"
)

func backendFixture(t *testing.T, project string, writes *atomic.Int32) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer fixture" {
			t.Error("missing existing CLI authentication")
		}
		var call struct {
			Tool  string         `json:"tool"`
			Input map[string]any `json:"input"`
		}
		if err := json.NewDecoder(r.Body).Decode(&call); err != nil {
			t.Error(err)
		}
		if call.Tool == "list" {
			_, _ = w.Write([]byte(`[{"id":"thread-one","project":"/project","title":"Review topic","messages":[{"body":"saved-history"}],"source":{"lines":["PRIVATE_SNAPSHOT"]},"queue":[{"message":"PRIVATE_QUEUE_PAYLOAD"}]}]`))
			return
		}
		if call.Tool == "read" {
			_, _ = w.Write([]byte(`{"project":"/another-project"}`))
			return
		}
		writes.Add(1)
		if call.Input["project"] != project || call.Input["author"] != "pi" {
			t.Errorf("wrong scope: %v", call.Input)
		}
		_, _ = w.Write([]byte(`"thread-result"`))
	}))
}

func connectBackend(t *testing.T, url string) string {
	t.Helper()
	directory := t.TempDir()
	if err := executor.SaveConfig(directory, executor.Config{URL: url, Organization: "org", App: "app"}); err != nil {
		t.Fatal(err)
	}
	// This is an isolated test token, never a user's connection file.
	raw, err := json.Marshal(map[string]any{"access_token": "fixture", "expires_at": time.Now().Add(time.Hour).Unix(), "token_endpoint": url + "/token", "resource": url + "/api"})
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(filepath.Join(directory, "executor-session.json"), raw, 0o600); err != nil {
		t.Fatal(err)
	}
	return directory
}

// TestSingleReadPreservesTheBackendResponse avoids duplicate full reads.
func TestSingleReadPreservesTheBackendResponse(t *testing.T) {
	t.Parallel()
	project, err := inbox.Project(t.Context(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var reads atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		reads.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]any{"project": project, "id": "own", "future_field": true})
	}))
	defer server.Close()
	result, err := Call(t.Context(), connectBackend(t, server.URL), project, strings.NewReader(`{"action":"read","input":{"thread":"own"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if reads.Load() != 1 || !strings.Contains(string(result), `"future_field":true`) {
		t.Fatalf("read count=%d result=%s", reads.Load(), result)
	}
}

func namedInboxBackend(t *testing.T, writes *atomic.Int32) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var call struct {
			Tool  string         `json:"tool"`
			Input map[string]any `json:"input"`
		}
		if err := json.NewDecoder(r.Body).Decode(&call); err != nil {
			t.Error(err)
		}
		if call.Tool == "read" {
			_, _ = w.Write([]byte(`{"id":"shared","project":"/another-project","inbox":"agent-friction"}`))
			return
		}
		if call.Tool == "list" {
			if _, exists := call.Input["project"]; exists {
				t.Error("named list was narrowed to current origin")
			}
			_, _ = w.Write([]byte(`[]`))
			return
		}
		if _, exists := call.Input["inbox"]; exists {
			t.Error("bridge forwarded inbox to a thread-only tool")
		}
		writes.Add(1)
		_, _ = w.Write([]byte(`{"id":"reply"}`))
	}))
}

// TestNamedInboxScope keeps the default project boundary intact.
func TestNamedInboxScope(t *testing.T) {
	t.Parallel()
	var writes atomic.Int32
	server := namedInboxBackend(t, &writes)
	defer server.Close()
	directory, project := connectBackend(t, server.URL), t.TempDir()
	for _, input := range []string{
		`{"action":"read","input":{"inbox":"agent-friction","thread":"shared"}}`,
		`{"action":"list","input":{"inbox":"agent-friction"}}`,
		`{"action":"reply","input":{"inbox":"agent-friction","thread":"shared","body":"Recorded"}}`,
	} {
		if _, err := Call(t.Context(), directory, project, strings.NewReader(input)); err != nil {
			t.Fatal(err)
		}
	}
	for _, input := range []string{
		`{"action":"reply","input":{"thread":"shared","body":"Wrong scope"}}`,
		`{"action":"reply","input":{"inbox":"ideas","thread":"shared","body":"Wrong destination"}}`,
	} {
		if _, err := Call(t.Context(), directory, project, strings.NewReader(input)); err == nil {
			t.Fatal("accepted mismatched destination")
		}
	}
	if writes.Load() != 1 {
		t.Fatalf("unexpected writes: %d", writes.Load())
	}
}

// TestOversizedRequestRejectsValidPrefix prevents truncation before a mutation.
func TestOversizedRequestRejectsValidPrefix(t *testing.T) {
	t.Parallel()
	input := `{"action":"create","input":{"body":"question"}}` + strings.Repeat(" ", 4*1024*1024) + "{}"
	if _, err := decodeCall(strings.NewReader(input)); err == nil || !strings.Contains(err.Error(), "exceeds 4 MiB") {
		t.Fatalf("accepted truncated input: %v", err)
	}
}

// TestBackendAdapterScopesCalls verifies the adapter uses existing
// authenticated transport and refuses another project's thread before writing.
func TestBackendAdapterScopesCalls(t *testing.T) {
	t.Parallel()
	project, err := inbox.Project(t.Context(), t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var writes atomic.Int32
	server := backendFixture(t, project, &writes)
	defer server.Close()
	directory := connectBackend(t, server.URL)
	result, err := Call(t.Context(), directory, project, strings.NewReader(`{"action":"create","input":{"body":"question"}}`))
	if err != nil || string(result) != `"thread-result"` {
		t.Fatalf("result=%s error=%v", result, err)
	}
	listed, err := Call(t.Context(), directory, project, strings.NewReader(`{"action":"list","input":{}}`))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(listed), `"message_count":1`) || strings.Contains(string(listed), "PRIVATE_") || strings.Contains(string(listed), "saved-history") {
		t.Fatalf("list exposed complete records: %s", listed)
	}
	if _, err = Call(t.Context(), directory, project, strings.NewReader(`{"action":"reply","input":{"thread":"foreign","body":"wrong"}}`)); err == nil {
		t.Fatal("cross-project write accepted")
	}
	if writes.Load() != 1 {
		t.Fatalf("unexpected writes: %d", writes.Load())
	}
	if _, err = Call(t.Context(), directory, project, strings.NewReader(`{"action":"agents.select","input":{}}`)); err == nil {
		t.Fatal("unrestricted operation accepted")
	}
}
