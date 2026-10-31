// Package rex opens Commentry tools in Rex.
package rex

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const sessionIDKey = "session_id"

// Client addresses the Rex session and app that initiated an action.
type Client struct {
	Session    string
	Block      string
	Client     string
	DeferFocus bool
}

func (c Client) call(ctx context.Context, method string, args any, result any) error {
	raw, err := json.Marshal(args)
	if err != nil {
		return err
	}
	argv := []string{"api", "call", method, string(raw)}
	// #nosec G204 -- CLI and method are fixed; JSON arguments are never shell code.
	command := exec.CommandContext(ctx, "rex", argv...)
	output, err := command.Output()
	if err != nil {
		var message string
		if exit, ok := err.(*exec.ExitError); ok {
			message = strings.TrimSpace(string(exit.Stderr))
		}
		return fmt.Errorf("rex %s: %w %s", method, err, message)
	}
	if result == nil {
		return nil
	}
	return json.Unmarshal(output, result)
}

// Project reads the originating pane's reported directory.
func (c Client) Project(ctx context.Context) (string, error) {
	if c.Session == "" || c.Block == "" {
		return "", fmt.Errorf("capture requires a Rex session and originating pane")
	}
	var processes struct {
		Foreground struct {
			Cwd string `json:"cwd"`
		} `json:"foreground"`
	}
	args := map[string]any{sessionIDKey: c.Session, "block_id": c.Block, "method": "process", "args": map[string]any{}}
	// Foreground cwd also works for panes without shell OSC directory reporting,
	// and does not retain a stale shell directory while an editor is running.
	if err := c.call(ctx, "block.method", args, &processes); err == nil && filepath.IsAbs(processes.Foreground.Cwd) {
		return filepath.Clean(processes.Foreground.Cwd), nil
	}
	var result struct {
		Pwd string `json:"pwd"`
	}
	args["method"] = "pwd"
	if err := c.call(ctx, "block.method", args, &result); err != nil {
		return "", err
	}
	uri, err := url.Parse(result.Pwd)
	if err != nil {
		return "", err
	}
	if uri.Scheme != "file" || uri.Path == "" {
		return "", fmt.Errorf("pane has no known directory; pass --project explicitly")
	}
	return filepath.Clean(uri.Path), nil
}

// WindowFor returns the tab containing a pane, using the current session view.
func (c Client) WindowFor(ctx context.Context) (string, error) {
	var view struct {
		Windows []struct {
			ID     string `json:"window_id"`
			Layers []struct {
				Blocks []struct {
					ID string `json:"block_id"`
				} `json:"blocks"`
			} `json:"layers"`
		} `json:"windows"`
	}
	if err := c.call(ctx, "session.view", map[string]string{sessionIDKey: c.Session}, &view); err != nil {
		return "", err
	}
	for _, window := range view.Windows {
		for _, layer := range window.Layers {
			for _, block := range layer.Blocks {
				if block.ID == c.Block {
					return window.ID, nil
				}
			}
		}
	}
	return "", fmt.Errorf("originating pane no longer exists")
}

// Open starts a command in a tab on the originating app.
func (c Client) Open(ctx context.Context, title, project string, command []string) (string, error) {
	var result struct {
		Window string `json:"window_id"`
	}
	if err := c.call(ctx, "session.new_window", map[string]any{sessionIDKey: c.Session, "window_label": title, "layout": map[string]any{"block": map[string]any{"flavor": "com.superlogical.terminal.shell", "options": map[string]any{"command": append([]string{"env", "PATH=" + os.Getenv("PATH")}, command...), "shell": "none", "cwd": project}}}}, &result); err != nil {
		return "", err
	}
	if result.Window == "" {
		return "", fmt.Errorf("rex created a tab without returning its ID; inspect Rex before retrying")
	}
	// Let the app receive the new view before selecting it. Never retry
	// creation, since a late reply could otherwise create duplicate editors.
	if c.DeferFocus {
		return result.Window, nil
	}
	select {
	case <-time.After(200 * time.Millisecond):
	case <-ctx.Done():
		return result.Window, ctx.Err()
	}
	if err := c.Focus(ctx, result.Window); err != nil {
		return result.Window, fmt.Errorf("tab %s created but focus failed: %w", result.Window, err)
	}
	return result.Window, nil
}

// Focus selects an existing tab on the same app that initiated the action.
func (c Client) Focus(ctx context.Context, window string) error {
	if c.Client == "" {
		var clients struct {
			Clients []struct {
				ID   string `json:"client_id"`
				Info struct {
					Kind string `json:"kind"`
				} `json:"info"`
			} `json:"clients"`
		}
		if err := c.call(ctx, "client.list", map[string]any{}, &clients); err != nil {
			return err
		}
		for _, client := range clients.Clients {
			if client.Info.Kind == "app" {
				if c.Client != "" {
					return fmt.Errorf("multiple Rex apps are connected; pass --client")
				}
				c.Client = client.ID
			}
		}
		if c.Client == "" {
			return fmt.Errorf("no Rex app is connected")
		}
	}
	return c.call(ctx, "client.perform", map[string]any{"client_id": c.Client, "action": "session.select", "args": map[string]string{sessionIDKey: c.Session, "window_id": window}}, nil)
}
