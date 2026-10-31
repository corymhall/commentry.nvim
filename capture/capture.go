// Package capture opens a short-lived Neovim composer for external comments.
package capture

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/corymhall/commentry.nvim/inbox"
)

//go:embed composer.lua
var composer string //nolint:gochecknoglobals // Immutable embedded UI asset.

// Options identifies the immutable capture and its destination.
type Options struct {
	Project   string  `json:"project"`
	Text      *string `json:"text,omitempty"`
	Directory string  `json:"directory"`
}

// Run starts a dedicated editor process. A failed save leaves its draft open.
func Run(ctx context.Context, options Options, stdin io.Reader, stdout, stderr io.Writer) error {
	var err error
	options.Project, err = inbox.Project(ctx, options.Project)
	if err != nil {
		return err
	}
	if options.Directory == "" {
		options.Directory, err = inbox.DefaultDirectory()
		if err != nil {
			return err
		}
	}
	options.Directory, err = filepath.Abs(options.Directory)
	if err != nil {
		return err
	}
	directory, err := os.MkdirTemp("", "commentry-capture-")
	if err != nil {
		return err
	}
	defer func() { _ = os.RemoveAll(directory) }()
	data, err := json.Marshal(options)
	if err != nil {
		return err
	}
	config := filepath.Join(directory, "capture.json")
	script := filepath.Join(directory, "composer.lua")
	if err = os.WriteFile(config, data, 0o600); err != nil {
		return err
	}
	if err = os.WriteFile(script, []byte(composer), 0o600); err != nil {
		return err
	}
	// #nosec G204 -- Fixed editor program; user text travels through a private JSON file.
	command := exec.CommandContext(ctx, "nvim", "-n", "-i", "NONE", "-c", `lua dofile(vim.env.COMMENTRY_CAPTURE_SCRIPT)`)
	command.Dir = options.Project
	command.Env = append(os.Environ(), "COMMENTRY_CAPTURE_SCRIPT="+script, "COMMENTRY_CAPTURE_CONFIG="+config)
	command.Stdin, command.Stdout, command.Stderr = stdin, stdout, stderr
	if err = command.Run(); err != nil {
		return fmt.Errorf("capture editor: %w", err)
	}
	return nil
}
