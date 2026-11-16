package cmd

import (
	"github.com/corymhall/commentry.nvim/agent"
	"github.com/corymhall/commentry.nvim/inbox"
	"github.com/spf13/cobra"
)

func newAgent(directory *string) *cobra.Command {
	root := &cobra.Command{Use: "agent", Short: "Connect to an existing Pi or Codex agent in Rex"}
	var project string
	root.PersistentFlags().StringVar(&project, "project", "", "Project directory")
	list := &cobra.Command{Use: actionList, Short: "Discover running sessions in this project", Args: cobra.NoArgs}
	list.RunE = func(command *cobra.Command, _ []string) error {
		result, err := agent.Discover(command.Context(), project)
		return emit(command, result, err)
	}
	attach := &cobra.Command{Use: "attach <target>", Short: "Select an existing Rex agent and deliver pending comments", Args: cobra.ExactArgs(1)}
	attach.RunE = func(command *cobra.Command, args []string) error {
		a, err := agent.Attach(command.Context(), *directory, project, args[0])
		if err != nil {
			return emit(command, nil, err)
		}
		sent, dispatchErr := agent.DispatchOnAttach(command.Context(), *directory, a.Project)
		result := map[string]any{"agent": a, "sent": sent}
		if dispatchErr != nil {
			result["delivery_error"] = dispatchErr.Error()
		}
		return emit(command, result, nil)
	}
	root.AddCommand(list, attach, newAgentBatch(directory, &project), newAgentNotify(directory, &project))
	for _, action := range []string{"status", "dispatch", "detach", "focus", "steer"} {
		root.AddCommand(newAgentControl(action, directory, &project))
	}
	return root
}

func selectedAgent(command *cobra.Command, directory, project string) (inbox.Agent, error) {
	canonical, err := inbox.Project(command.Context(), project)
	if err != nil {
		return inbox.Agent{}, err
	}
	store, err := inbox.Open(command.Context(), directory)
	if err != nil {
		return inbox.Agent{}, err
	}
	defer func() { _ = store.Close() }()
	return store.Agent(command.Context(), canonical)
}

func newAgentControl(action string, directory, project *string) *cobra.Command {
	command := &cobra.Command{Use: action, Short: action + " the selected existing session", Args: cobra.NoArgs}
	if action == "steer" {
		command.Use += " <thread>"
		command.Args = cobra.ExactArgs(1)
	}
	command.RunE = func(command *cobra.Command, args []string) error {
		a, err := selectedAgent(command, *directory, *project)
		if err != nil {
			return emit(command, nil, err)
		}
		switch action {
		case "status":
			result, err := agent.Inspect(command.Context(), a)
			return emit(command, result, err)
		case "detach":
			store, err := inbox.Open(command.Context(), *directory)
			if err != nil {
				return emit(command, nil, err)
			}
			defer func() { _ = store.Close() }()
			return emit(command, map[string]bool{"detached": true}, store.DetachAgent(command.Context(), a.Project, a.ID))
		case "focus":
			return emit(command, a, agent.Focus(command.Context(), a))
		case "steer":
			result, err := agent.Steer(command.Context(), *directory, *project, args[0])
			return emit(command, result, err)
		default:
			sent, err := agent.Dispatch(command.Context(), *directory, *project, "", "")
			return emit(command, map[string]int{"sent": sent}, err)
		}
	}
	return command
}

func newAgentBatch(directory, project *string) *cobra.Command {
	var ids []string
	command := &cobra.Command{Use: "dispatch-batch", Short: "Submit selected pending requests in one native queue message", Args: cobra.NoArgs}
	command.Flags().StringSliceVar(&ids, "queue-id", nil, "Pending request IDs to include")
	_ = command.MarkFlagRequired("queue-id")
	command.RunE = func(command *cobra.Command, _ []string) error {
		sent, err := agent.DispatchBatch(command.Context(), *directory, *project, ids)
		result := map[string]any{"sent": sent}
		if err != nil {
			result["delivery_error"] = err.Error()
		}
		return emit(command, result, nil)
	}
	return command
}
