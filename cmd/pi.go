package cmd

import (
	"github.com/corymhall/commentry.nvim/pibridge"
	"github.com/spf13/cobra"
)

func newPi(directory *string) *cobra.Command {
	var project string
	root := &cobra.Command{Use: "pi", Short: "Local Pi extension backend adapter"}
	root.PersistentFlags().StringVar(&project, "project", "", "Current project directory")
	context := &cobra.Command{Use: "context", Short: "Resolve the current project and inbox without exposing credentials", Args: cobra.NoArgs}
	context.RunE = func(command *cobra.Command, _ []string) error {
		result, err := pibridge.Context(command.Context(), *directory, project)
		return emit(command, result, err)
	}
	rpc := &cobra.Command{Use: "rpc", Short: "Call an allowlisted Commentry operation for the current project", Args: cobra.NoArgs}
	rpc.RunE = func(command *cobra.Command, _ []string) error {
		result, err := pibridge.Call(command.Context(), *directory, project, command.InOrStdin())
		return emit(command, result, err)
	}
	root.AddCommand(context, rpc)
	return root
}
