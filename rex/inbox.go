package rex

import (
	"context"
	"fmt"
	"math"
	"os"
	"sort"
)

// InboxTarget identifies the pane used to display the inbox.
type InboxTarget struct {
	Window string `json:"window"`
	Block  string `json:"block"`
	Reused bool   `json:"reused"`
}

type layoutNode struct {
	Block string                               `json:"block_id"`
	Rect  [4]float64                           `json:"rect"`
	Split *struct{ Before, After *layoutNode } `json:"split"`
}

type paneRect struct {
	block string
	rect  [4]float64
}

func flatten(node *layoutNode) []paneRect {
	if node == nil {
		return nil
	}
	if node.Block != "" {
		return []paneRect{{block: node.Block, rect: node.Rect}}
	}
	if node.Split == nil {
		return nil
	}
	return append(flatten(node.Split.Before), flatten(node.Split.After)...)
}

func beside(origin, pane paneRect) bool {
	overlap := math.Min(origin.rect[1]+origin.rect[3], pane.rect[1]+pane.rect[3]) - math.Max(origin.rect[1], pane.rect[1])
	touches := math.Abs(origin.rect[0]+origin.rect[2]-pane.rect[0]) < 0.001 || math.Abs(pane.rect[0]+pane.rect[2]-origin.rect[0]) < 0.001
	return overlap > 0.001 && touches
}

func neighbors(panes []paneRect, block string) []paneRect {
	var origin paneRect
	for _, pane := range panes {
		if pane.block == block {
			origin = pane
			break
		}
	}
	if origin.block == "" {
		return nil
	}
	result := []paneRect{origin}
	for _, pane := range panes {
		if pane.block != block && beside(origin, pane) {
			result = append(result, pane)
		}
	}
	sort.SliceStable(result[1:], func(i, j int) bool {
		a, b := result[i+1], result[j+1]
		return math.Abs(a.rect[1]+a.rect[3]/2-origin.rect[1]-origin.rect[3]/2) < math.Abs(b.rect[1]+b.rect[3]/2-origin.rect[1]-origin.rect[3]/2)
	})
	return result
}

func (c Client) inboxNeighbors(ctx context.Context) (string, []paneRect, error) {
	var view struct {
		Windows []struct {
			ID     string `json:"window_id"`
			Layers []struct {
				Layout *layoutNode `json:"layout"`
			} `json:"layers"`
		} `json:"windows"`
	}
	if err := c.call(ctx, "session.view", map[string]string{sessionIDKey: c.Session}, &view); err != nil {
		return "", nil, err
	}
	for _, window := range view.Windows {
		for _, layer := range window.Layers {
			if panes := neighbors(flatten(layer.Layout), c.Block); len(panes) > 0 {
				return window.ID, panes, nil
			}
		}
	}
	return "", nil, fmt.Errorf("originating pane no longer exists")
}

func (c Client) neovimPID(ctx context.Context, block string) (int, error) {
	type process struct {
		PID  int    `json:"pid"`
		Name string `json:"name"`
	}
	var result struct {
		Foreground process   `json:"foreground"`
		Ancestors  []process `json:"ancestors"`
	}
	if err := c.call(ctx, "block.method", map[string]any{sessionIDKey: c.Session, "block_id": block, "method": "process", "args": map[string]any{}}, &result); err != nil {
		return 0, err
	}
	for _, p := range append([]process{result.Foreground}, result.Ancestors...) {
		if p.Name == "nvim" {
			return p.PID, nil
		}
	}
	return 0, nil
}

// OpenInbox reuses Neovim in the current or a horizontally adjacent pane.
// If none exists, it creates a right-hand split in the same Rex window.
func (c Client) OpenInbox(ctx context.Context, project, directory, binary string) (InboxTarget, error) {
	window, panes, err := c.inboxNeighbors(ctx)
	if err != nil {
		return InboxTarget{}, err
	}
	for _, pane := range panes {
		pid, err := c.neovimPID(ctx, pane.block)
		if err != nil {
			return InboxTarget{}, err
		}
		if pid == 0 {
			continue
		}
		if err = c.openNeovim(ctx, pane.block, pid, project, directory, binary); err != nil {
			return InboxTarget{}, err
		}
		target := InboxTarget{Window: window, Block: pane.block, Reused: true}
		return target, c.focusInbox(ctx, target)
	}
	command := []string{"env", "PATH=" + os.Getenv("PATH"), "COMMENTRY_INBOX_DIR=" + directory, "COMMENTRY_CLI=" + binary, "nvim", "-c", `lua require("commentry.inbox").open()`}
	var created struct {
		Blocks []string `json:"block_ids"`
	}
	err = c.call(ctx, "session.new_split", map[string]any{
		sessionIDKey: c.Session, "anchor_block_id": c.Block, "direction": "horizontal", "side": "after", "ratio": 0.5, "focus": false,
		"layout": map[string]any{"block": map[string]any{"flavor": "com.superlogical.terminal.shell", "options": map[string]any{"command": command, "shell": "none", "cwd": project}}},
	}, &created)
	if err != nil {
		return InboxTarget{}, err
	}
	if len(created.Blocks) != 1 || created.Blocks[0] == "" {
		return InboxTarget{}, fmt.Errorf("rex created a split without identifying its pane; inspect before retrying")
	}
	target := InboxTarget{Window: window, Block: created.Blocks[0]}
	return target, c.focusInbox(ctx, target)
}

func (c Client) focusInbox(ctx context.Context, target InboxTarget) error {
	if err := c.call(ctx, "session.focus_block", map[string]string{sessionIDKey: c.Session, "block_id": target.Block}, nil); err != nil {
		return err
	}
	if c.DeferFocus {
		return nil
	}
	return c.Focus(ctx, target.Window)
}
