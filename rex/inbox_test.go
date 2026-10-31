package rex

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// TestMain provides a fake Rex server transport with real Neovim RPC clients.
func TestMain(m *testing.M) {
	if file := os.Getenv("COMMENTRY_TEST_PANES"); file != "" {
		if err := fakePaneCall(file); err != nil {
			_, _ = fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		os.Exit(0)
	}
	os.Exit(m.Run())
}

type paneFixture struct {
	PID    int
	Layout string
	Log    string
}

func fakePaneCall(file string) error {
	// #nosec G304 G703 -- The parent test selects this private fixture file.
	raw, err := os.ReadFile(file)
	if err != nil {
		return err
	}
	var fixture paneFixture
	if err = json.Unmarshal(raw, &fixture); err != nil {
		return err
	}
	if len(os.Args) != 5 || os.Args[1] != "api" || os.Args[2] != "call" {
		return fmt.Errorf("unexpected invocation: %v", os.Args)
	}
	var args map[string]any
	if err = json.Unmarshal([]byte(os.Args[4]), &args); err != nil {
		return err
	}
	// #nosec G304 G703 -- The fixture's append-only log is in its private directory.
	log, err := os.OpenFile(fixture.Log, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	args["method_name"] = os.Args[3]
	err = json.NewEncoder(log).Encode(args)
	closeErr := log.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	result, err := fakePaneResult(fixture, os.Args[3], args)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(result)
}

func fakePaneResult(fixture paneFixture, method string, args map[string]any) (any, error) {
	var result any = map[string]any{}
	switch method {
	case "session.view":
		var layout any
		if err := json.Unmarshal([]byte(fixture.Layout), &layout); err != nil {
			return nil, err
		}
		result = map[string]any{"windows": []any{map[string]any{"window_id": "window", "layers": []any{map[string]any{"layout": layout}}}}}
	case "block.method":
		if args["method"] == "write" {
			data := args["args"].(map[string]any)["data"].(string)
			return map[string]int{"bytes_written": len(data)}, nil
		}
		if args["method"] != "process" {
			return nil, fmt.Errorf("unexpected terminal method")
		}
		name, pid := "codex", 123
		if args["block_id"] == "editor" {
			name, pid = "nvim", fixture.PID
		}
		result = map[string]any{"foreground": map[string]any{"name": name, "pid": pid}}
	case "session.new_split":
		result = map[string]any{"block_ids": []string{"created"}}
	case "session.focus_block":
	default:
		return nil, fmt.Errorf("unexpected Rex mutation: %s", method)
	}
	return result, nil
}

func setupPanes(t *testing.T, pid int, left bool) (Client, string) {
	t.Helper()
	root := t.TempDir()
	before, after := "origin", "editor"
	if left {
		before, after = after, before
	}
	layout := fmt.Sprintf(`{"rect":[0,0,1,1],"split":{"before":{"block_id":%q,"rect":[0,0,0.5,1]},"after":{"block_id":%q,"rect":[0.5,0,0.5,1]}}}`, before, after)
	fixture := paneFixture{PID: pid, Layout: layout, Log: filepath.Join(root, "calls.jsonl")}
	if pid == 0 {
		fixture.Layout = `{"block_id":"origin","rect":[0,0,1,1]}`
	}
	raw, err := json.Marshal(fixture)
	if err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(root, "fixture.json")
	if err = os.WriteFile(file, raw, 0o600); err != nil {
		t.Fatal(err)
	}
	binary, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Symlink(binary, filepath.Join(root, "rex")); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", root+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("COMMENTRY_TEST_PANES", file)
	return Client{Session: "session", Block: "origin", DeferFocus: true}, fixture.Log
}

func paneCalls(t *testing.T, path string) []map[string]any {
	t.Helper()
	// #nosec G304 -- The log is generated inside the private test directory.
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var result []map[string]any
	for line := range strings.SplitSeq(strings.TrimSpace(string(raw)), "\n") {
		var call map[string]any
		if err = json.Unmarshal([]byte(line), &call); err != nil {
			t.Fatal(err)
		}
		result = append(result, call)
	}
	return result
}

func startEditor(t *testing.T) int {
	t.Helper()
	root, err := os.MkdirTemp("/tmp", "commentry-rpc-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(root) })
	t.Setenv("TMPDIR", root+string(os.PathSeparator))
	t.Setenv("XDG_RUNTIME_DIR", "")
	if err = os.Unsetenv("XDG_RUNTIME_DIR"); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NVIM", "")
	// The receiver records arguments while retaining an unsaved user buffer.
	bootstrap := `lua vim.cmd.enew(); vim.api.nvim_buf_set_lines(0,0,-1,false,{'unsaved draft'}); vim.g.draft_buffer=vim.api.nvim_get_current_buf(); package.preload['commentry.inbox']=function() return {open=function(_,opts) vim.g.inbox_project=opts.project; vim.cmd.tabnew() end} end`
	bootstrap += "; vim.fn.writefile({vim.v.servername,tostring(vim.fn.getpid())}," + strconv.Quote(filepath.Join(root, "ready")) + ")"
	command := exec.CommandContext(t.Context(), "nvim", "--headless", "-u", "NONE", "-i", "NONE", "-c", bootstrap)
	command.Stderr = os.Stderr
	input, err := command.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = input.Close() })
	if err = command.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = command.Process.Kill(); _ = command.Wait() })
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if _, err = neovimSocket(t.Context(), command.Process.Pid); err == nil {
			return command.Process.Pid
		}
		time.Sleep(10 * time.Millisecond)
	}
	// #nosec G304 -- Neovim writes this startup diagnostic in the private fixture.
	raw, _ := os.ReadFile(filepath.Join(root, "ready"))
	t.Fatalf("Neovim RPC did not start for PID %d: %s; %v", command.Process.Pid, raw, err)
	return 0
}

// TestInboxReusesSideEditors protects drafts and scope on either side.
func TestInboxReusesSideEditors(t *testing.T) {
	for _, left := range []bool{false, true} {
		t.Run(fmt.Sprintf("left=%t", left), func(t *testing.T) { testReuseEditor(t, left) })
	}
}

func testReuseEditor(t *testing.T, left bool) {
	t.Helper()
	pid := startEditor(t)
	client, log := setupPanes(t, pid, left)
	socket, err := neovimSocket(t.Context(), pid)
	if err != nil {
		t.Fatal(err)
	}
	cwd, err := neovimEval(t.Context(), socket, "getcwd()")
	if err != nil {
		t.Fatal(err)
	}
	project := "/project with 'quotes'"
	result, err := client.OpenInbox(t.Context(), project, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if !result.Reused || result.Block != "editor" || result.Window != "window" {
		t.Fatalf("incorrect target: %+v", result)
	}
	assertEditorState(t, socket, cwd, project)
	for _, call := range paneCalls(t, log) {
		if call["method_name"] == "session.new_split" {
			t.Fatal("created another pane despite adjacent Neovim")
		}
	}
}

func assertEditorState(t *testing.T, socket, cwd, project string) {
	t.Helper()
	actual, err := neovimEval(t.Context(), socket, `json_encode([getcwd(),g:inbox_project,getbufline(g:draft_buffer,1,'$'),getbufvar(g:draft_buffer,'&modified')])`)
	if err != nil {
		t.Fatal(err)
	}
	var state []any
	if err = json.Unmarshal([]byte(actual), &state); err != nil {
		t.Fatal(err)
	}
	if state[0] != cwd || state[1] != project || state[2].([]any)[0] != "unsaved draft" || state[3] != float64(1) {
		t.Fatalf("editor state changed: %s", actual)
	}
}

// TestInboxCreatesRightSplit checks layout and command when no editor exists.
func TestInboxCreatesRightSplit(t *testing.T) {
	client, log := setupPanes(t, 0, false)
	result, err := client.OpenInbox(t.Context(), "/project", "/data")
	if err != nil {
		t.Fatal(err)
	}
	if result.Reused || result.Block != "created" {
		t.Fatalf("incorrect target: %+v", result)
	}
	found := false
	for _, call := range paneCalls(t, log) {
		if call["method_name"] == "session.new_split" {
			found = true
			if call["direction"] != "horizontal" || call["side"] != "after" || call["anchor_block_id"] != "origin" {
				t.Fatalf("wrong split: %+v", call)
			}
		}
	}
	if !found {
		t.Fatal("no right-hand split created")
	}
}

// TestInboxWithoutRPCReusesEditor checks the Normal-mode fallback command.
func TestInboxWithoutRPCReusesEditor(t *testing.T) {
	client, log := setupPanes(t, 99999999, false)
	result, err := client.OpenInbox(context.Background(), "/project", "/data")
	if err != nil {
		t.Fatal(err)
	}
	if !result.Reused {
		t.Fatal("did not reuse the editor")
	}
	found := false
	for _, call := range paneCalls(t, log) {
		if call["method_name"] == "session.new_split" {
			t.Fatal("created duplicate editor without RPC")
		}
		if call["method"] == "write" {
			found = true
			data := call["args"].(map[string]any)["data"].(string)
			if !strings.HasPrefix(data, "\x1b\x1c\x0e:call luaeval(") || !strings.HasSuffix(data, "\r") {
				t.Fatalf("unsafe editor command: %q", data)
			}
		}
	}
	if !found {
		t.Fatal("did not send editor command")
	}
}
