package cmd

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	"github.com/corymhall/commentry.nvim/inbox"
	"github.com/spf13/cobra"
)

func newPublish(directory *string) *cobra.Command {
	var file string
	command := &cobra.Command{Use: "publish", Short: "Atomically publish review topics from a JSON manifest", Args: cobra.NoArgs}
	command.Flags().StringVar(&file, "file", "-", "Publication manifest, or - for stdin")
	command.RunE = func(command *cobra.Command, _ []string) error {
		reader := command.InOrStdin()
		if file != "-" {
			// #nosec G304 -- The user explicitly selects the publication manifest.
			opened, err := os.Open(file)
			if err != nil {
				return emit(command, nil, err)
			}
			defer func() { _ = opened.Close() }()
			reader = opened
		}
		decoder := json.NewDecoder(reader)
		decoder.DisallowUnknownFields()
		var request inbox.Request
		if err := decoder.Decode(&request); err != nil {
			return emit(command, nil, err)
		}
		var extra any
		if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
			return emit(command, nil, fmt.Errorf("expected exactly one publication manifest"))
		}
		if request.Action != "" && request.Action != "publish" {
			return emit(command, nil, fmt.Errorf("manifest action must be publish"))
		}
		request.Action = "publish"
		result, err := execute(command, *directory, request)
		return emit(command, result, err)
	}
	return command
}
