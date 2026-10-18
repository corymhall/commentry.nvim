package cmd_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/corymhall/commentry.nvim/cmd"
	"github.com/corymhall/commentry.nvim/inbox"
)

// TestRPCValidationAndErrorEnvelope checks structured request failures.
func TestRPCValidationAndErrorEnvelope(t *testing.T) {
	t.Parallel()
	for _, input := range []string{`null`, `{"action":"list"} {}`, `{"action":"reply","thread":"missing","body":"reply"}`} {
		root := cmd.NewRootCmd()
		root.SetArgs([]string{"--directory", t.TempDir(), "rpc"})
		root.SetIn(strings.NewReader(input))
		var output bytes.Buffer
		root.SetOut(&output)
		root.SetErr(&output)
		if err := root.ExecuteContext(t.Context()); err == nil {
			t.Fatalf("accepted %s", input)
		}
		var response struct {
			OK    bool   `json:"ok"`
			Error string `json:"error"`
		}
		if err := json.Unmarshal(output.Bytes(), &response); err != nil {
			t.Fatal(err)
		}
		if response.OK || response.Error == "" {
			t.Fatal("failure did not produce structured error")
		}
	}
}

type outputChannel struct{ messages chan []byte }

func (o outputChannel) Write(p []byte) (int, error) { o.messages <- bytes.Clone(p); return len(p), nil }

// TestWatchReceivesExternalChangesAndCancels checks notification delivery.
func TestWatchReceivesExternalChangesAndCancels(t *testing.T) {
	t.Parallel()
	directory := t.TempDir()
	project := t.TempDir()
	store, err := inbox.Open(t.Context(), directory)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := store.Close(); err != nil {
			t.Error(err)
		}
	}()
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	root := cmd.NewRootCmd()
	root.SetArgs([]string{"--directory", directory, "watch", "--project", project})
	output := outputChannel{messages: make(chan []byte, 4)}
	root.SetOut(output)
	done := make(chan error, 1)
	go func() { done <- root.ExecuteContext(ctx) }()
	receive := func() []byte {
		t.Helper()
		select {
		case message := <-output.messages:
			return message
		case <-time.After(5 * time.Second):
			t.Fatal("watch did not emit changes")
			return nil
		}
	}
	receive()
	result, err := store.Execute(t.Context(), inbox.Request{Action: "create", Project: project, Body: "New request"})
	if err != nil {
		t.Fatal(err)
	}
	message := receive()
	if !bytes.Contains(message, []byte(result.(string))) {
		t.Fatalf("watch missed created thread: %s", message)
	}
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("watch returned %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("watch ignored cancellation")
	}
}
