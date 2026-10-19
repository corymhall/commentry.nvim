package inbox_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/corymhall/commentry.nvim/executor"
	"github.com/corymhall/commentry.nvim/inbox"
)

// TestConfiguredExecutorNeverFallsBack prevents split local and remote history.
func TestConfiguredExecutorNeverFallsBack(t *testing.T) {
	t.Parallel()
	directory := t.TempDir()
	local := openStore(t, directory)
	id := run(t, local, inbox.Request{Action: "create", Project: t.TempDir(), Body: "Original local record"}).(string)
	if err := executor.SaveConfig(directory, executor.Config{URL: "https://executor.invalid", Organization: "org", App: "app"}); err != nil {
		t.Fatal(err)
	}
	remote, err := inbox.Open(t.Context(), directory)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = remote.Close() }()
	if _, err = remote.Execute(t.Context(), inbox.Request{Action: "reply", Thread: id, Body: "Must not become a local reply"}); err == nil {
		t.Fatal("unavailable Executor accepted a reply")
	}
	if err = os.Remove(filepath.Join(directory, "executor.json")); err != nil {
		t.Fatal(err)
	}
	current := run(t, local, inbox.Request{Action: "read", Thread: id}).(inbox.Thread)
	if len(current.Messages) != 1 {
		t.Fatal("failed remote write silently mutated the legacy database")
	}
}
