package executor

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// TestInterruptedMutationIsNeverReplayed protects against duplicate effects.
func TestInterruptedMutationIsNeverReplayed(t *testing.T) {
	t.Parallel()
	var writes atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-access" {
			t.Error("missing authentication")
		}
		writes.Add(1)
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte(`{"message":"upstream disconnected after acceptance"}`))
	}))
	defer server.Close()
	directory := t.TempDir()
	if err := writeJSON(directory, "executor-session.json", session{Access: "test-access", Expires: time.Now().Add(time.Hour).Unix(), TokenEndpoint: server.URL + "/token"}); err != nil {
		t.Fatal(err)
	}
	client := Client{Directory: directory, Config: Config{URL: server.URL, Organization: "org", App: "app"}}
	if err := client.Call(t.Context(), "finish", map[string]string{"thread": "thread"}, nil); err == nil {
		t.Fatal("accepted failed response")
	}
	if writes.Load() != 1 {
		t.Fatalf("replayed mutation %d times", writes.Load())
	}
}

// TestConcurrentRefreshSerializesRotation protects shared CLI credentials.
func TestConcurrentRefreshSerializesRotation(t *testing.T) {
	t.Parallel()
	var refreshes atomic.Int32
	server := refreshingServer(t, &refreshes)
	defer server.Close()
	directory := t.TempDir()
	if err := writeJSON(directory, "executor-session.json", session{Client: "test", Refresh: "first", TokenEndpoint: server.URL + "/token", Resource: server.URL + "/api"}); err != nil {
		t.Fatal(err)
	}
	client := Client{Directory: directory, Config: Config{URL: server.URL, Organization: "org", App: "app"}}
	var workers sync.WaitGroup
	for range 4 {
		workers.Go(func() {
			var revision int
			if err := client.Call(t.Context(), "revision", struct{}{}, &revision); err != nil || revision != 7 {
				t.Errorf("revision=%d, error=%v", revision, err)
			}
		})
	}
	workers.Wait()
	if refreshes.Load() != 1 {
		t.Fatalf("rotated the token %d times", refreshes.Load())
	}
}

// TestDeviceApprovalStaysWithUser checks pending, resource and token semantics.
func TestDeviceApprovalStaysWithUser(t *testing.T) {
	t.Parallel()
	var origin string
	var approved atomic.Bool
	var devices atomic.Int32
	server := deviceServer(t, &approved, &devices)
	defer server.Close()
	origin = server.URL
	directory := t.TempDir()
	pending, err := BeginLogin(t.Context(), directory, Config{URL: origin, App: "app", Organization: "org"})
	if err != nil {
		t.Fatal(err)
	}
	resumed, resumeErr := BeginLogin(t.Context(), directory, Config{URL: origin, App: "app", Organization: "org"})
	if resumeErr != nil || resumed.DeviceCode != pending.DeviceCode || devices.Load() != 1 {
		t.Fatalf("login did not resume its existing request: %v", resumeErr)
	}
	if pending.Code != "CODE" {
		t.Fatal("did not return browser approval code")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 20*time.Millisecond)
	defer cancel()
	if err = CompleteLogin(ctx, directory, pending); err == nil {
		t.Fatal("created a session before approval")
	}
	approved.Store(true)
	if err = CompleteLogin(t.Context(), directory, pending); err != nil {
		t.Fatal(err)
	}
}

func refreshingServer(t *testing.T, refreshes *atomic.Int32) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/token" {
			refreshes.Add(1)
			if err := r.ParseForm(); err != nil {
				t.Error(err)
			}
			if r.Form.Get("refresh_token") != "first" {
				t.Error("reused a superseded refresh token")
			}
			// #nosec G117 -- These are dummy tokens issued only by an isolated test server.
			_ = json.NewEncoder(w).Encode(tokenResponse{Access: "renewed", Refresh: "second", Expires: 3600})
			return
		}
		if r.Header.Get("Authorization") != "Bearer renewed" {
			t.Error("missing renewed session")
		}
		_, _ = w.Write([]byte(`7`))
	}))
}

// TestDeviceRateLimitKeepsPendingRequest checks the server-directed pause.
func TestDeviceRateLimitKeepsPendingRequest(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.Header().Set("Retry-After", "90")
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer server.Close()
	_, delay, err := exchangeDevice(t.Context(), DeviceLogin{token: server.URL})
	if err != nil || delay != 90*time.Second || calls.Load() != 1 {
		t.Fatalf("rate limit did not pause the same request: %v, %v, %d", delay, err, calls.Load())
	}
}

func deviceServer(t *testing.T, approved *atomic.Bool, devices *atomic.Int32) *httptest.Server {
	t.Helper()
	var server *httptest.Server
	server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/.well-known/oauth-authorization-server":
			_ = json.NewEncoder(w).Encode(metadata{Issuer: server.URL, Registration: server.URL + "/register", Device: server.URL + "/device", Token: server.URL + "/token"})
		case "/register":
			_, _ = w.Write([]byte(`{"client_id":"test-client"}`))
		case "/device":
			devices.Add(1)
			if err := r.ParseForm(); err != nil {
				t.Error(err)
			}
			if r.Form.Get("resource") != server.URL+"/api" {
				t.Error("wrong OAuth resource")
			}
			_, _ = w.Write([]byte(`{"verification_uri":"https://example.com/device","user_code":"CODE","device_code":"private-device","interval":1,"expires_in":10}`))
		case "/token":
			if !approved.Load() {
				w.WriteHeader(400)
				_, _ = w.Write([]byte(`{"error":"authorization_pending"}`))
				return
			}
			// #nosec G117 -- These are dummy tokens issued only by an isolated test server.
			_ = json.NewEncoder(w).Encode(tokenResponse{Access: "approved", Refresh: "refresh", Expires: 3600})
		}
	}))
	return server
}
