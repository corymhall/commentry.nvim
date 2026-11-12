package cmd

import (
	"github.com/corymhall/commentry.nvim/agent"
	"github.com/spf13/cobra"
)

func newAgentNotify(directory, project *string) *cobra.Command {
	var queueID string
	var handoff bool
	command := &cobra.Command{Use: "notify <thread>", Short: "Notify the selected agent again about an outstanding request", Args: cobra.ExactArgs(1)}
	command.Flags().StringVar(&queueID, "queue-id", "", "Outstanding request ID")
	command.Flags().BoolVar(&handoff, "handoff", false, "Explicitly invalidate the old claim when changing agents")
	_ = command.MarkFlagRequired("queue-id")
	command.RunE = func(command *cobra.Command, args []string) error {
		sent, err := agent.Notify(command.Context(), *directory, *project, args[0], queueID, handoff)
		return emit(command, map[string]int{"sent": sent}, err)
	}
	return command
}
