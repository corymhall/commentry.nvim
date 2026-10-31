package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/corymhall/commentry.nvim/agent"
	"github.com/corymhall/commentry.nvim/capture"
	"github.com/corymhall/commentry.nvim/inbox"
	"github.com/corymhall/commentry.nvim/rex"
	"github.com/spf13/cobra"
)

func newRex(directory *string) *cobra.Command {
	root := &cobra.Command{Use: "rex", Short: "Open Commentry tools in Rex"}
	var target rex.Client
	var project string
	root.PersistentFlags().StringVar(&target.Session, "session", os.Getenv("REX_SESSION"), "Originating Rex session")
	root.PersistentFlags().StringVar(&target.Block, "block", os.Getenv("REX_BLOCK"), "Originating Rex pane")
	root.PersistentFlags().StringVar(&target.Client, "client", os.Getenv("REX_CLIENT"), "Originating Rex app")
	root.PersistentFlags().StringVar(&project, "project", "", "Project directory, otherwise inferred from originating pane")
	root.PersistentFlags().BoolVar(&target.DeferFocus, "defer-focus", false, "Let the invoking Rex action select the target window")
	var empty bool
	command := &cobra.Command{Use: "capture", Short: "Open a clipboard composer in a temporary Rex tab", Args: cobra.NoArgs}
	command.Flags().BoolVar(&empty, "empty", false, "Start a standalone comment")
	command.RunE = func(command *cobra.Command, _ []string) error {
		return openCapture(command, *directory, project, target, empty)
	}
	var input, returnWindow string
	editor := &cobra.Command{Use: "capture-editor", Hidden: true, Args: cobra.NoArgs, RunE: func(command *cobra.Command, _ []string) error {
		// #nosec G304 -- The originating capture command supplies its private snapshot file.
		data, err := os.ReadFile(input)
		if err != nil {
			return err
		}
		var options capture.Options
		if err = json.Unmarshal(data, &options); err != nil {
			return err
		}
		if options.Project == "" || !strings.HasPrefix(filepath.Base(input), "commentry-clipboard-") {
			return fmt.Errorf("not a private Commentry capture snapshot")
		}
		if err = os.Remove(input); err != nil {
			return err
		}
		err = capture.Run(command.Context(), options, command.InOrStdin(), command.OutOrStdout(), command.ErrOrStderr())
		if err != nil {
			return err
		}
		// The terminal exits naturally. Never close the origin or another user's tab.
		focusCtx, cancel := context.WithTimeout(command.Context(), 3*time.Second)
		defer cancel()
		if focusErr := target.Focus(focusCtx, returnWindow); focusErr != nil {
			_, _ = fmt.Fprintln(command.ErrOrStderr(), "Comment saved or cancelled; could not return to original tab:", focusErr)
		}
		return nil
	}}
	editor.Flags().StringVar(&input, "input", "", "Private clipboard snapshot")
	editor.Flags().StringVar(&returnWindow, "return-window", "", "Originating tab")
	root.AddCommand(command, editor, newRexInbox(directory, &project, &target))
	return root
}

func resolveDirectory(directory string) (string, error) {
	if directory == "" {
		var err error
		directory, err = inbox.DefaultDirectory()
		if err != nil {
			return "", err
		}
	}
	return filepath.Abs(directory)
}

func openCapture(command *cobra.Command, directory, project string, target rex.Client, empty bool) error {
	ctx := command.Context()
	if project == "" {
		var err error
		project, err = target.Project(ctx)
		if err != nil {
			return err
		}
	}
	canonical, err := inbox.Project(ctx, project)
	if err != nil {
		return err
	}
	// The capture editor starts in the project, which may differ from the
	// caller's directory. Resolve the destination before changing processes.
	directory, err = resolveDirectory(directory)
	if err != nil {
		return err
	}
	origin, err := target.WindowFor(ctx)
	if err != nil {
		return err
	}
	options := capture.Options{Project: canonical, Directory: directory}
	if !empty {
		output, readErr := exec.CommandContext(ctx, "/usr/bin/pbpaste").Output()
		if readErr != nil {
			return fmt.Errorf("read clipboard: %w", readErr)
		}
		text := string(output)
		options.Text = &text
	}
	// Snapshot now, before changing focus or starting the editor.
	filename, err := writeCapture(options)
	if err != nil {
		return err
	}
	window, err := target.Open(ctx, "New comment", canonical, []string{"commentry", "--directory", directory, "rex", "--session", target.Session, "--client", target.Client, "capture-editor", "--input", filename, "--return-window", origin})
	if err != nil {
		// A timed out creation may have started the editor. Keep its private
		// snapshot available rather than invalidating an already-created tab.
		return err
	}
	return emit(command, map[string]string{"window": window}, nil)
}

func writeCapture(options capture.Options) (string, error) {
	file, err := os.CreateTemp("", "commentry-clipboard-*.json")
	if err != nil {
		return "", err
	}
	filename := file.Name()
	if err = json.NewEncoder(file).Encode(options); err != nil {
		_ = file.Close()
		_ = os.Remove(filename)
		return "", err
	}
	if err = file.Close(); err != nil {
		_ = os.Remove(filename)
		return "", err
	}
	return filename, nil
}

func newRexInbox(directory, project *string, target *rex.Client) *cobra.Command {
	return &cobra.Command{Use: "inbox", Short: "Open the inbox in a neighboring Neovim pane or a right-hand split", Args: cobra.NoArgs, RunE: func(command *cobra.Command, _ []string) error {
		ctx := command.Context()
		path := *project
		if path == "" {
			var err error
			path, err = target.Project(ctx)
			if err != nil {
				return err
			}
		}
		canonical, err := inbox.Project(ctx, path)
		if err != nil {
			return err
		}
		data, err := resolveDirectory(*directory)
		if err != nil {
			return err
		}
		if err = selectOriginAgent(ctx, data, canonical, *target); err != nil {
			return err
		}
		result, err := target.OpenInbox(ctx, canonical, data)
		return emit(command, result, err)
	}}
}

func selectOriginAgent(ctx context.Context, directory, project string, target rex.Client) error {
	discovered, err := agent.Discover(ctx, project)
	if err != nil {
		return err
	}
	for _, candidate := range discovered.Sessions {
		if candidate.RexSession == target.Session && candidate.RexBlock == target.Block {
			_, err = agent.Attach(ctx, directory, project, candidate.ID)
			return err
		}
	}
	return nil
}
