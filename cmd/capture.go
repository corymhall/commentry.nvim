package cmd

import (
	"fmt"
	"os/exec"
	"runtime"

	"github.com/corymhall/commentry.nvim/capture"
	"github.com/spf13/cobra"
)

func newCapture(directory *string) *cobra.Command {
	var project string
	var empty bool
	command := &cobra.Command{Use: "capture", Short: "Comment on the clipboard in a temporary editor", Args: cobra.NoArgs}
	command.Flags().StringVar(&project, "project", "", "Project directory")
	command.Flags().BoolVar(&empty, "empty", false, "Start a standalone comment without reading the clipboard")
	command.RunE = func(command *cobra.Command, _ []string) error {
		options := capture.Options{Project: project, Directory: *directory}
		if !empty {
			if runtime.GOOS != "darwin" {
				return fmt.Errorf("clipboard capture currently requires macOS; use --empty or create --text")
			}
			output, err := exec.CommandContext(command.Context(), "/usr/bin/pbpaste").Output()
			if err != nil {
				return fmt.Errorf("read clipboard: %w", err)
			}
			text := string(output)
			options.Text = &text
		}
		return capture.Run(command.Context(), options, command.InOrStdin(), command.OutOrStdout(), command.ErrOrStderr())
	}
	return command
}
