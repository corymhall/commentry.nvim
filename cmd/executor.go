package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"github.com/corymhall/commentry.nvim/executor"
	"github.com/corymhall/commentry.nvim/inbox"
	"github.com/spf13/cobra"
)

func newExecutor(directory *string) *cobra.Command {
	root := &cobra.Command{Use: "executor", Short: "Connect the inbox to its Executor backend"}
	var config executor.Config
	login := &cobra.Command{Use: "login", Short: "Sign in through Executor's browser device approval", Args: cobra.NoArgs}
	login.Flags().StringVar(&config.URL, "url", "", "Executor origin")
	login.Flags().StringVar(&config.Organization, "organization", "", "Executor organization ID or slug")
	login.Flags().StringVar(&config.App, "app", "", "Commentry app ID")
	login.RunE = func(command *cobra.Command, _ []string) error { return loginExecutor(command, *directory, config) }
	var filename string
	migrate := &cobra.Command{Use: "import", Short: "Import an explicit legacy export into the configured app", Args: cobra.NoArgs}
	migrate.Flags().StringVar(&filename, "file", "", "JSON snapshot exported before connecting")
	migrate.RunE = func(command *cobra.Command, _ []string) error { return importExecutor(command, *directory, filename) }
	export := &cobra.Command{Use: "export", Short: "Export the current inbox and selections before changing backends", Args: cobra.NoArgs, RunE: func(command *cobra.Command, _ []string) error {
		return exportExecutor(command, *directory)
	}}
	status := &cobra.Command{Use: "status", Short: "Show the selected app without exposing credentials", Args: cobra.NoArgs, RunE: func(command *cobra.Command, _ []string) error {
		data, err := resolveDirectory(*directory)
		if err != nil {
			return err
		}
		client, err := executor.Open(data)
		if err != nil {
			if executor.IsUnconfigured(err) {
				return emit(command, map[string]string{"backend": "legacy-local", "directory": filepath.Clean(data)}, nil)
			}
			return err
		}
		return emit(command, client.Config, nil)
	}}
	root.AddCommand(login, migrate, export, status)
	return root
}

func loginExecutor(command *cobra.Command, directory string, config executor.Config) error {
	data, err := resolveDirectory(directory)
	if err != nil {
		return err
	}
	if current, openErr := executor.Open(data); openErr == nil {
		if config.URL == "" {
			config.URL = current.Config.URL
		}
		if config.Organization == "" {
			config.Organization = current.Config.Organization
		}
		if config.App == "" {
			config.App = current.Config.App
		}
	} else if !executor.IsUnconfigured(openErr) {
		return openErr
	}
	pending, err := executor.BeginLogin(command.Context(), data, config)
	if err != nil {
		return err
	}
	link := pending.CompleteURL
	if link == "" {
		link = pending.URL
	}
	if _, err = fmt.Fprintf(command.ErrOrStderr(), "Open %s\nApprove code %s for Commentry. This grants Executor account access.\n", link, pending.Code); err != nil {
		return err
	}
	if err = executor.CompleteLogin(command.Context(), data, pending); err != nil {
		return err
	}
	client := &executor.Client{Config: config, Directory: data}
	var revision int64
	if err = client.Call(command.Context(), "revision", struct{}{}, &revision); err != nil {
		return err
	}
	// Verify access before atomically selecting the hosted backend.
	if err = executor.SaveConfig(data, config); err != nil {
		return err
	}
	return emit(command, map[string]any{"connected": true, "revision": revision}, nil)
}

func importExecutor(command *cobra.Command, directory, filename string) error {
	data, err := resolveDirectory(directory)
	if err != nil {
		return err
	}
	client, err := executor.Open(data)
	if err != nil {
		return err
	}
	// #nosec G304 -- The user explicitly names the exported snapshot.
	raw, err := os.ReadFile(filename)
	if err != nil {
		return err
	}
	var snapshot struct {
		Threads []inbox.Thread `json:"threads"`
		Agents  []inbox.Agent  `json:"agents"`
	}
	if err = json.Unmarshal(raw, &snapshot); err != nil {
		return err
	}
	var result any
	err = client.Call(command.Context(), "migration.import", snapshot, &result)
	return emit(command, result, err)
}

func exportExecutor(command *cobra.Command, directory string) error {
	store, err := inbox.Open(command.Context(), directory)
	if err != nil {
		return err
	}
	defer func() { _ = store.Close() }()
	result, err := store.Execute(command.Context(), inbox.Request{Action: actionList})
	if err != nil {
		return err
	}
	threads := result.([]inbox.Thread)
	agents := []inbox.Agent{}
	seen := map[string]bool{}
	for _, t := range threads {
		if seen[t.Project] {
			continue
		}
		seen[t.Project] = true
		a, readErr := store.Agent(command.Context(), t.Project)
		if readErr != nil {
			return readErr
		}
		if a.ID != "" {
			agents = append(agents, a)
		}
	}
	return json.NewEncoder(command.OutOrStdout()).Encode(map[string]any{"threads": threads, "agents": agents})
}
