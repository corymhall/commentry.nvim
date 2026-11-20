// Package cmd builds Commentry's command-line interface.
package cmd

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/corymhall/commentry.nvim/agent"
	"github.com/corymhall/commentry.nvim/inbox"
	"github.com/spf13/cobra"
)

const (
	actionRead              = "read"
	actionList              = "list"
	actionQueue             = "queue"
	actionFinish            = "finish"
	actionResolve           = "resolve"
	actionComparison        = "comparison"
	actionReadState         = "read-state"
	actionRevise            = "revise"
	actionArchiveComparison = "archive-comparison"
)

// NewRootCmd constructs an independent command tree for each invocation.
func NewRootCmd() *cobra.Command {
	var directory string
	root := &cobra.Command{
		Use: "commentry", Short: "Project inbox for people and coding agents",
		SilenceUsage: true, SilenceErrors: true,
		RunE: func(command *cobra.Command, _ []string) error { return command.Help() },
	}
	root.PersistentFlags().StringVar(&directory, "directory", "", "Inbox data directory, defaults to COMMENTRY_INBOX_DIR or Neovim's data directory")
	for _, action := range []string{actionList, actionRead, "create", "reply", actionFinish, actionResolve, actionComparison, actionArchiveComparison, actionRevise, "attach", actionReadState, actionQueue, "claim", "complete", "acknowledge", "cancel", "retry", "revision", "changes"} {
		root.AddCommand(newAction(action, &directory))
	}
	root.AddCommand(newPi(&directory), newPublish(&directory), newAction("publication", &directory), newRPC(&directory), newWatch(&directory), newCapture(&directory), newRex(&directory), newAgent(&directory), newExecutor(&directory))
	return root
}

type response struct {
	OK     bool   `json:"ok"`
	Result any    `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

func emit(command *cobra.Command, result any, failure error) error {
	output := response{OK: failure == nil, Result: result}
	if failure != nil {
		output.Error = failure.Error()
	}
	if err := json.NewEncoder(command.OutOrStdout()).Encode(output); err != nil {
		return errors.Join(failure, err)
	}
	return failure
}

func execute(command *cobra.Command, directory string, request inbox.Request) (result any, err error) {
	store, err := inbox.Open(command.Context(), directory)
	if err != nil {
		return nil, err
	}
	defer func() { err = errors.Join(err, store.Close()) }()
	deferred := request.DeferDelivery
	request.DeferDelivery = false // Local transport option, never forwarded to Executor.
	result, err = store.Execute(command.Context(), request)
	if err != nil || request.Action != actionQueue || deferred {
		return result, err
	}
	queued := result.(inbox.Queued)
	if queued.Status != "pending" {
		return queued, nil
	}
	value, err := store.Execute(command.Context(), inbox.Request{Action: actionRead, Thread: request.Thread})
	if err != nil {
		return result, err
	}
	thread := value.(inbox.Thread)
	sent, deliveryErr := agent.Dispatch(command.Context(), directory, thread.Project, thread.ID, queued.ID)
	if sent > 0 {
		queued.Skipped = false
	}
	if deliveryErr != nil {
		queued.DeliveryError = deliveryErr.Error()
	}
	value, err = store.Execute(command.Context(), inbox.Request{Action: actionRead, Thread: request.Thread})
	if err != nil {
		return result, err
	}
	for _, current := range value.(inbox.Thread).Queue {
		if current.ID == queued.ID {
			current.DeliveryError = queued.DeliveryError
			current.Skipped = queued.Skipped
			return current, nil
		}
	}
	return queued, nil
}

func newRPC(directory *string) *cobra.Command {
	return &cobra.Command{
		Use: "rpc", Short: "Read one JSON request from stdin and return one JSON response", Args: cobra.NoArgs,
		RunE: func(command *cobra.Command, _ []string) error {
			request, err := decode(command.InOrStdin())
			if err != nil {
				return emit(command, nil, err)
			}
			result, err := execute(command, *directory, request)
			return emit(command, result, err)
		},
	}
}

func decode(reader io.Reader) (inbox.Request, error) {
	var request inbox.Request
	decoder := json.NewDecoder(reader)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		return request, fmt.Errorf("decode request: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return request, fmt.Errorf("expected exactly one JSON request")
	}
	if request.Action == "" {
		return request, fmt.Errorf("action is required")
	}
	return request, nil
}

func newAction(action string, directory *string) *cobra.Command {
	options := actionOptions{request: inbox.Request{Action: action}}
	request := &options.request
	command := &cobra.Command{Use: action, Short: actionDescription(action), Args: cobra.NoArgs}
	flags := command.Flags()
	switch action {
	case actionRead, "attach", "reply", actionFinish, actionResolve, actionComparison, actionArchiveComparison, actionRevise, actionReadState, actionQueue, "complete", "acknowledge", "cancel", "retry":
		command.Use += " <thread>"
		command.Args = cobra.ExactArgs(1)
	}
	flags.StringVar(&request.Project, "project", "", "Originating project directory, Git root is inferred")
	if action == actionList || action == "create" || action == "changes" || action == "publication" {
		flags.StringVar(&request.Inbox, "inbox", "", "Named cross-project inbox destination")
	}
	flags.StringVar(&request.Author, "author", "", "Author label, defaults to You; required for claim")
	bindActionFlags(command, &options)
	command.RunE = func(command *cobra.Command, args []string) error {
		if err := options.prepare(command, args); err != nil {
			return emit(command, nil, err)
		}
		result, err := execute(command, *directory, options.request)
		return emit(command, result, err)
	}
	return command
}

type actionOptions struct {
	request                                                    inbox.Request
	text, sourceFile, beforeFile, afterFile, primaryComparison string
	resolved, read                                             bool
}

func bindActionFlags(command *cobra.Command, options *actionOptions) {
	request := &options.request
	action := request.Action
	flags := command.Flags()
	if action == "publication" {
		flags.StringVar(&request.RequestID, "request-id", "", "Publication request ID")
	}
	switch action {
	case "list":
		flags.StringVar(&request.Filter, "filter", "all", "all, unread, read, open, resolved, or queued")
		flags.BoolVar(&request.Summary, "summary", false, "Omit full source snapshots")
	case "create":
		flags.StringVar(&request.Title, "title", "", "Thread title")
		flags.StringVar(&request.Body, "body", "", "Comment body")
		flags.StringVar(&options.text, "text", "", "Copied text to capture")
		flags.StringVar(&options.sourceFile, "source-file", "", "JSON file containing an immutable source capture")
	case actionRevise:
		flags.StringVar(&request.Title, "title", "", "Current review title")
		flags.StringVar(&request.Body, "body", "", "Current review summary")
		flags.StringVar(&request.ExpectedReview, "expected-review", "", "Current review version required when revising")
		flags.StringVar(&options.primaryComparison, "primary-comparison", "", "Comparison to show first; empty clears the selection")
	case "attach":
		flags.StringVar(&options.sourceFile, "source-file", "", "JSON file containing a file snapshot")
		flags.StringVar(&request.Label, "label", "", "Location label")
		flags.StringVar(&request.AttachmentID, "attachment-id", "", "Replace this attachment, preserving its ID")
	case "reply", "finish":
		flags.StringVar(&request.RequestID, "request-id", "", "Durable reply ID for idempotent retries")
		flags.StringVar(&request.Body, "body", "", "Reply body")
		if action == actionFinish {
			flags.StringSliceVar(&request.ClaimIDs, "claim-id", nil, "Active claim IDs completed atomically with this reply")
		}
	case actionResolve:
		flags.BoolVar(&options.resolved, "resolved", true, "Set false to reopen")
	case actionReadState:
		flags.BoolVar(&options.read, actionRead, true, "Set false to mark unread")
		flags.StringVar(&request.Seen, "seen", "", "Incoming version displayed to the reader")
	case actionArchiveComparison:
		flags.StringVar(&request.ComparisonID, "comparison-id", "", "Your comparison to withdraw from the active review")
	case actionComparison:
		flags.StringVar(&request.ComparisonID, "comparison-id", "", "Replace your comparison, preserving its ID")
		flags.StringVar(&options.beforeFile, "before-file", "", "File containing the comparison's before text")
		flags.StringVar(&options.afterFile, "after-file", "", "File containing the comparison's after text")
		flags.StringVar(&request.Label, "label", "", "Comparison label")
	case actionQueue:
		flags.BoolVar(&request.DeferDelivery, "defer-delivery", false, "Save the request without submitting it to Rex")
		flags.StringVar(&request.Message, "message", "", "Explicit immutable request, otherwise capture thread context")
	case "complete", "acknowledge":
		flags.StringVar(&request.ClaimID, "claim-id", "", "Active claim ID")
	case "retry":
		flags.StringVar(&request.QueueID, "queue-id", "", "Failed request to retry after inspecting partial work")
	case "cancel":
		flags.StringVar(&request.QueueID, "queue-id", "", "Queued request ID")
		flags.BoolVar(&request.PendingOnly, "pending-only", false, "Refuse to cancel claimed work")
	case "changes":
		flags.Int64Var(&request.Cursor, "after", 0, "Resume after this change sequence")
	}
}

func (options *actionOptions) prepare(command *cobra.Command, args []string) error {
	request := &options.request
	action := request.Action
	flags := command.Flags()
	if len(args) > 0 {
		request.Thread = args[0]
	}
	if action == actionRevise && flags.Changed("primary-comparison") {
		request.PrimaryComparison = &options.primaryComparison
	}
	if action == actionResolve {
		request.Resolved = &options.resolved
	}
	if action == actionReadState {
		request.Read = &options.read
	}
	if flags.Changed("text") {
		request.Text = &options.text
	}
	if err := options.prepareSource(); err != nil {
		return err
	}
	if action == actionComparison {
		before, err := readInputFile(options.beforeFile)
		if err != nil {
			return err
		}
		after, err := readInputFile(options.afterFile)
		if err != nil {
			return err
		}
		b, a := string(before), string(after)
		request.Before = &b
		request.After = &a
	}
	return nil
}

func (options *actionOptions) prepareSource() error {
	if options.sourceFile == "" {
		return nil
	}
	raw, err := readInputFile(options.sourceFile)
	if err != nil {
		return err
	}
	var source inbox.Source
	if err = json.Unmarshal(raw, &source); err != nil {
		return err
	}
	options.request.Source = &source
	return nil
}

func readInputFile(filename string) ([]byte, error) {
	// #nosec G304 -- These are local files explicitly selected by CLI flags.
	return os.ReadFile(filename)
}

func actionDescription(action string) string {
	if action == "publication" {
		return "Look up the receipt for an atomic publication"
	}
	descriptions := map[string]string{
		"attach":                "Add or replace a named code attachment",
		actionArchiveComparison: "Withdraw your comparison while preserving its history",
		actionRevise:            "Revise the review summary and choose primary evidence",
		actionList:              "List project threads and filter their state", actionRead: "Read a thread without marking it read",
		"create": "Create a standalone or captured-text thread", "reply": "Reply to a thread", actionResolve: "Resolve or reopen a conversation",
		"finish":         "Reply and complete the specified active claims in one transaction",
		actionComparison: "Attach an agent-authored before/after comparison", actionReadState: "Mark a displayed incoming version read, or mark unread",
		actionQueue: "Queue an immutable request for an agent", "claim": "Atomically claim the oldest pending request in a project",
		"complete": "Complete an active claim without resolving its thread", "cancel": "Cancel a pending or claimed request",
		"retry":    "Retry a failed request after inspecting partial work",
		"revision": "Read the current change sequence", "changes": "Read a page of committed changes after a cursor",
	}
	return descriptions[action]
}

func newWatch(directory *string) *cobra.Command {
	var project string
	var cursor int64
	var timeout time.Duration
	command := &cobra.Command{Use: "watch", Short: "Stream committed changes as JSON lines until cancelled", Args: cobra.NoArgs}
	command.Flags().StringVar(&project, "project", "", "Watch only this project")
	command.Flags().Int64Var(&cursor, "after", 0, "Resume after this change sequence")
	command.Flags().DurationVar(&timeout, "timeout", 0, "Stop after this duration, zero waits until cancelled")
	command.RunE = func(command *cobra.Command, _ []string) error {
		return watch(command, *directory, project, cursor, timeout)
	}
	return command
}

func watch(command *cobra.Command, directory, project string, cursor int64, timeout time.Duration) (err error) {
	if timeout < 0 {
		return fmt.Errorf("timeout cannot be negative")
	}
	store, err := inbox.Open(command.Context(), directory)
	if err != nil {
		return err
	}
	defer func() { err = errors.Join(err, store.Close()) }()
	if project != "" {
		project, err = inbox.Project(command.Context(), project)
		if err != nil {
			return err
		}
	}
	var deadline <-chan time.Time
	if timeout > 0 {
		timer := time.NewTimer(timeout)
		defer timer.Stop()
		deadline = timer.C
	}
	return streamChanges(command, store, project, cursor, deadline)
}

func streamChanges(command *cobra.Command, store *inbox.Store, project string, cursor int64, deadline <-chan time.Time) error {
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()
	first := true
	for {
		select {
		case <-command.Context().Done():
			return command.Context().Err()
		case <-deadline:
			return nil
		default:
		}
		page, err := store.Changes(command.Context(), project, cursor)
		if err != nil {
			return emit(command, nil, err)
		}
		if first || len(page.Changes) > 0 {
			if err = emit(command, page, nil); err != nil {
				return err
			}
			first = false
		}
		cursor = page.Cursor
		if len(page.Changes) == 100 {
			continue
		}
		select {
		case <-command.Context().Done():
			return command.Context().Err()
		case <-deadline:
			return nil
		case <-ticker.C:
		}
	}
}
