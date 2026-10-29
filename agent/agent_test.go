package agent

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/corymhall/commentry.nvim/inbox"
)

// TestMain supplies a fake Rex CLI without a running server.
func TestMain(m *testing.M) {
	if filename := os.Getenv("COMMENTRY_TEST_REX_FIXTURE"); filename != "" {
		if err := fakeRexAction(filename); err != nil {
			_, _ = fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		os.Exit(0)
	}
	os.Exit(m.Run())
}

type rexFixture struct {
	Agent  rexAgent   `json:"agent"`
	Others []rexAgent `json:"others,omitempty"`
	Reject bool       `json:"reject"`
}

func fakeRexAction(filename string) error {
	// #nosec G304 G703 -- This is the private fixture selected by the parent test.
	raw, err := os.ReadFile(filename)
	if err != nil {
		return err
	}
	var fixture rexFixture
	if err = json.Unmarshal(raw, &fixture); err != nil {
		return err
	}
	if len(os.Args) != 7 || os.Args[1] != "--autostart=false" || os.Args[2] != "do" {
		return fmt.Errorf("unexpected Rex invocation: %v", os.Args)
	}
	action := os.Args[3]
	var args map[string]string
	if err = json.NewDecoder(os.Stdin).Decode(&args); err != nil {
		return err
	}
	switch action {
	case "agent_list":
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"agents": append([]rexAgent{fixture.Agent}, fixture.Others...)})
	case "agent_get":
		if args["target"] != fixture.Agent.ID {
			return fmt.Errorf("agent changed")
		}
		return json.NewEncoder(os.Stdout).Encode(fixture.Agent)
	case "agent_queue", "agent_steer", "agent_focus":
		return fakeRexDelivery(filename, action, args, fixture.Reject)
	default:
		return fmt.Errorf("unexpected action %s", action)
	}
}

func fakeRexDelivery(filename, action string, args map[string]string, reject bool) error {
	// #nosec G304 G703 -- The log lives beside the parent test's private fixture.
	file, err := os.OpenFile(filename+".log", os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	args["action"] = action
	writeErr := json.NewEncoder(file).Encode(args)
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	if closeErr != nil {
		return closeErr
	}
	if reject {
		return fmt.Errorf("test rejection")
	}
	return json.NewEncoder(os.Stdout).Encode(map[string]any{"submitted": true, "target": args["target"], "mode": strings.TrimPrefix(action, "agent_")})
}

type fixture struct {
	directory string
	project   string
	file      string
	agent     inbox.Agent
	native    rexFixture
	store     *inbox.Store
}

func fakeRex(t *testing.T) *fixture {
	t.Helper()
	root := t.TempDir()
	project, err := inbox.Project(t.Context(), root)
	if err != nil {
		t.Fatal(err)
	}
	f := &fixture{directory: filepath.Join(root, "data"), project: project, file: filepath.Join(root, "rex.json")}
	f.native.Agent = rexAgent{ID: "session/block/123", Session: "session", Block: "block", Harness: "codex", CWD: project, Name: "Existing Codex", State: "working"}
	f.agent = inbox.Agent{ID: f.native.Agent.ID, Harness: "codex", Project: project, RexSession: "session", RexBlock: "block"}
	f.save(t)
	binary, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	t.Setenv("COMMENTRY_REX", binary)
	t.Setenv("COMMENTRY_TEST_REX_FIXTURE", f.file)
	f.store, err = inbox.Open(t.Context(), f.directory)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = f.store.Close() })
	return f
}

func (f *fixture) save(t *testing.T) {
	t.Helper()
	raw, err := json.Marshal(f.native)
	if err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(f.file, raw, 0o600); err != nil {
		t.Fatal(err)
	}
}

func (f *fixture) deliveries(t *testing.T) []map[string]string {
	t.Helper()
	// #nosec G304 -- This is the private delivery log created by the fake Rex CLI.
	file, err := os.Open(f.file + ".log")
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = file.Close() }()
	var result []map[string]string
	decoder := json.NewDecoder(file)
	for decoder.More() {
		var entry map[string]string
		if err = decoder.Decode(&entry); err != nil {
			t.Fatal(err)
		}
		result = append(result, entry)
	}
	return result
}

func (f *fixture) execute(t *testing.T, r inbox.Request) any {
	t.Helper()
	result, err := f.store.Execute(t.Context(), r)
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func (f *fixture) queued(t *testing.T) string {
	t.Helper()
	thread := f.execute(t, inbox.Request{Action: "create", Project: f.project, Body: "Explain this"}).(string)
	f.execute(t, inbox.Request{Action: "queue", Thread: thread})
	return thread
}

// TestWorktreeDiscoveryAndDelivery covers worktree fallback and scope.
func TestWorktreeDiscoveryAndDelivery(t *testing.T) {
	f := fakeRex(t)
	git := func(directory string, args ...string) {
		t.Helper()
		// #nosec G204 -- Arguments and paths belong to isolated test repositories.
		output, err := exec.CommandContext(t.Context(), "git", append([]string{"-C", directory}, args...)...).CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, output)
		}
	}
	git(f.project, "init")
	git(f.project, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-m", "Initial")
	worktree := filepath.Join(t.TempDir(), "linked")
	git(f.project, "worktree", "add", "-b", "linked", worktree)
	f.native.Agent.CWD = worktree
	unrelated := f.native.Agent
	unrelated.ID = "unrelated"
	unrelated.CWD = filepath.Join(t.TempDir(), "clone")
	git(f.project, "clone", "--local", f.project, unrelated.CWD)
	f.native.Others = []rexAgent{unrelated}
	f.save(t)
	found, err := Discover(t.Context(), f.project)
	if err != nil || len(found.Sessions) != 1 || found.Sessions[0].ID != f.agent.ID {
		t.Fatalf("worktree fallback: %+v, %v", found, err)
	}
	if _, err = Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	thread := f.queued(t)
	if sent, err := Dispatch(t.Context(), f.directory, f.project, thread, ""); err != nil || sent != 1 {
		t.Fatalf("cross-worktree delivery: sent=%d, %v", sent, err)
	}
	exact := f.native.Agent
	exact.ID = "exact"
	exact.CWD = f.project
	f.native.Others = append(f.native.Others, exact)
	f.save(t)
	found, err = Discover(t.Context(), f.project)
	if err != nil || len(found.Sessions) != 1 || found.Sessions[0].ID != exact.ID {
		t.Fatalf("exact worktree preference: %+v, %v", found, err)
	}
	// A newly available exact match must not invalidate the explicit selection.
	if status, err := Inspect(t.Context(), f.agent); err != nil || status.State != "working" {
		t.Fatalf("selected fallback became invalid: %+v, %v", status, err)
	}
	f.native.Agent.CWD = unrelated.CWD
	f.save(t)
	if status, err := Inspect(t.Context(), f.agent); err != nil || status.State != "offline" {
		t.Fatalf("unrelated project accepted: %+v, %v", status, err)
	}
}

// TestNativeQueueAndReplyAfterDetach checks delivery and reply attribution.
func TestNativeQueueAndReplyAfterDetach(t *testing.T) {
	f := fakeRex(t)
	thread := f.queued(t)
	if sent, err := Dispatch(t.Context(), f.directory, f.project, "", ""); err != nil || sent != 0 {
		t.Fatalf("unselected delivery = %d, %v", sent, err)
	}
	a, err := Attach(t.Context(), f.directory, f.project, f.agent.ID)
	if err != nil {
		t.Fatal(err)
	}
	if sent, err := Dispatch(t.Context(), f.directory, f.project, "", ""); err != nil || sent != 1 {
		t.Fatalf("delivery = %d, %v", sent, err)
	}
	if sent, err := Dispatch(t.Context(), f.directory, f.project, "", ""); err != nil || sent != 0 {
		t.Fatalf("replayed delivery = %d, %v", sent, err)
	}
	messages := f.deliveries(t)
	current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	claim := current.Queue[0].ClaimID
	if len(messages) != 1 || messages[0]["action"] != "agent_queue" || messages[0]["target"] != a.ID || !strings.Contains(messages[0]["text"], claim) || !strings.Contains(messages[0]["text"], thread) {
		t.Fatalf("incorrectly addressed delivery: %+v", messages)
	}
	if len(current.Messages) != 1 || current.Queue[0].Status != "claimed" {
		t.Fatalf("acceptance was treated as an answer: %+v", current)
	}
	if err = f.store.DetachAgent(t.Context(), f.project, a.ID); err != nil {
		t.Fatal(err)
	}
	f.execute(t, inbox.Request{Action: "finish", Thread: thread, ClaimIDs: []string{claim}, Author: "codex", Body: "An answer from the existing session"})
	current = f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	if len(current.Messages) != 2 || current.Queue[0].Status != "complete" || current.Resolved {
		t.Fatalf("incorrect completion after detach: %+v", current)
	}
}

// TestSteerScopeAndNativeMode checks project boundaries and direct input.
func TestSteerScopeAndNativeMode(t *testing.T) {
	f := fakeRex(t)
	if _, err := Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	thread := f.execute(t, inbox.Request{Action: "create", Project: t.TempDir(), Body: "Another project"}).(string)
	if _, err := Steer(t.Context(), f.directory, f.project, thread); err == nil {
		t.Fatal("steered another project's thread")
	}
	current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	if len(current.Queue) != 0 {
		t.Fatal("scope rejection enqueued work")
	}
	thread = f.execute(t, inbox.Request{Action: "create", Project: f.project, Body: "Steer this"}).(string)
	if _, err := Steer(t.Context(), f.directory, f.project, thread); err != nil {
		t.Fatal(err)
	}
	result, err := Steer(t.Context(), f.directory, f.project, thread)
	if err != nil || !result.(inbox.Queued).Skipped {
		t.Fatalf("duplicate steering did not report a skipped send: %v, %v", result, err)
	}
	messages := f.deliveries(t)
	if len(messages) != 1 || messages[0]["action"] != "agent_steer" {
		t.Fatalf("native steer not used: %+v", messages)
	}
}

// TestUncertainDeliveryIsNotReplayed protects against duplicate effects.
func TestUncertainDeliveryIsNotReplayed(t *testing.T) {
	f := fakeRex(t)
	thread := f.queued(t)
	if _, err := Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	f.native.Reject = true
	f.save(t)
	if _, err := Dispatch(t.Context(), f.directory, f.project, "", ""); err == nil {
		t.Fatal("accepted a rejected delivery")
	}
	current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	if current.Queue[0].Status != "failed" || current.Queue[0].Error == "" {
		t.Fatalf("failure not retained: %+v", current.Queue)
	}
	if sent, err := Dispatch(t.Context(), f.directory, f.project, "", ""); err != nil || sent != 0 {
		t.Fatalf("replayed uncertain work: %d, %v", sent, err)
	}
	duplicate := f.execute(t, inbox.Request{Action: "queue", Thread: thread}).(inbox.Queued)
	if !duplicate.Skipped || duplicate.ID != current.Queue[0].ID || duplicate.DeliveryError == "" {
		t.Fatalf("ordinary send bypassed failed delivery: %+v", duplicate)
	}
	if sent, err := Dispatch(t.Context(), f.directory, f.project, thread, duplicate.ID); err != nil || sent != 0 || len(f.deliveries(t)) != 1 {
		t.Fatalf("ordinary send replayed uncertain work: %d, %v", sent, err)
	}
	f.execute(t, inbox.Request{Action: "retry", Thread: thread, QueueID: duplicate.ID})
	f.native.Reject = false
	f.save(t)
	if sent, err := Dispatch(t.Context(), f.directory, f.project, thread, duplicate.ID); err != nil || sent != 1 || len(f.deliveries(t)) != 2 {
		t.Fatalf("explicit retry did not deliver: %d, %v", sent, err)
	}
	if _, err := f.store.Execute(t.Context(), inbox.Request{Action: "finish", Thread: thread, Body: "Superseded answer", ClaimIDs: []string{current.Queue[0].ClaimID}}); err == nil {
		t.Fatal("superseded delivery finished a retried request")
	}
}

// TestLateAnswerAfterUncertainDelivery retains replies after a lost receipt.
func TestLateAnswerAfterUncertainDelivery(t *testing.T) {
	f := fakeRex(t)
	thread := f.queued(t)
	if _, err := Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	f.native.Reject = true
	f.save(t)
	if _, err := Dispatch(t.Context(), f.directory, f.project, "", ""); err == nil {
		t.Fatal("expected an uncertain delivery")
	}
	current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	f.execute(t, inbox.Request{Action: "finish", Thread: thread, Author: "codex", Body: "The accepted request is complete", ClaimIDs: []string{current.Queue[0].ClaimID}})
	current = f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	if len(current.Messages) != 2 || !current.Unread || current.Resolved || current.Queue[0].Status != "complete" {
		t.Fatalf("late answer was lost or resolved its thread: %+v", current)
	}
}

// TestReplacedAgentDoesNotReceiveOldRequests protects stale targets.
func TestReplacedAgentDoesNotReceiveOldRequests(t *testing.T) {
	f := fakeRex(t)
	thread := f.queued(t)
	if _, err := Attach(t.Context(), f.directory, f.project, f.agent.ID); err != nil {
		t.Fatal(err)
	}
	f.native.Agent.ID = "session/block/456"
	f.save(t)
	if _, err := Dispatch(t.Context(), f.directory, f.project, "", ""); err == nil {
		t.Fatal("delivered to a replacement agent")
	}
	current := f.execute(t, inbox.Request{Action: "read", Thread: thread}).(inbox.Thread)
	if current.Queue[0].Status != "pending" || len(f.deliveries(t)) != 0 {
		t.Fatal("stale selection consumed work")
	}
}
