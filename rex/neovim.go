package rex

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func neovimEval(ctx context.Context, socket, expression string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	// #nosec G204 -- Neovim is a configured runtime dependency; args bypass shells.
	command := exec.CommandContext(ctx, "nvim", "--server", socket, "--remote-expr", expression)
	raw, err := command.Output()
	if err != nil {
		detail := ""
		if exit, ok := err.(*exec.ExitError); ok {
			detail = strings.TrimSpace(string(exit.Stderr))
		}
		return "", fmt.Errorf("neovim RPC failed: %w %s", err, detail)
	}
	return strings.TrimSpace(string(raw)), nil
}

func neovimSocket(ctx context.Context, pid int) (string, error) {
	candidates, err := neovimSockets(pid)
	if err != nil {
		return "", err
	}
	for _, socket := range candidates {
		if socket == "" {
			continue
		}
		actual, err := neovimEval(ctx, socket, "getpid()")
		if err == nil && actual == strconv.Itoa(pid) {
			return socket, nil
		}
	}
	return "", fmt.Errorf("cannot find the RPC socket for Neovim process %d; keep its default RPC server enabled", pid)
}

func vimString(value string) string { return "'" + strings.ReplaceAll(value, "'", "''") + "'" }

func (c Client) openNeovim(ctx context.Context, block string, pid int, project, directory, binary string) error {
	options, err := json.Marshal(map[string]string{"project": project, "directory": directory, "binary": binary})
	if err != nil {
		return err
	}
	code := `(function() local o=_A; vim.cmd.stopinsert(); vim.env.COMMENTRY_INBOX_DIR=o.directory; vim.env.COMMENTRY_CLI=o.binary; require('commentry.inbox').open(nil,{project=o.project}); return true end)()`
	expression := "luaeval(" + vimString(code) + ",json_decode(" + vimString(string(options)) + "))"
	socket, socketErr := neovimSocket(ctx, pid)
	if socketErr == nil {
		_, err = neovimEval(ctx, socket, expression)
		return err
	}
	// Older editors may have no RPC listener. Return to Normal mode and execute
	// one command, preserving buffers and avoiding a duplicate editor process.
	current, err := c.neovimPID(ctx, block)
	if err != nil {
		return err
	}
	if current != pid {
		return fmt.Errorf("neovim process changed before opening the inbox")
	}
	data := "\x1b\x1c\x0e:call " + expression + "\r"
	var receipt struct {
		Bytes int `json:"bytes_written"`
	}
	err = c.call(ctx, "block.method", map[string]any{sessionIDKey: c.Session, "block_id": block, "method": "write", "args": map[string]string{"data": data}}, &receipt)
	if err != nil {
		return err
	}
	if receipt.Bytes != len(data) {
		return fmt.Errorf("editor command may be partial; inspect Neovim before retrying")
	}
	return nil
}

func neovimSockets(pid int) ([]string, error) {
	candidates := []string{os.Getenv("NVIM")}
	roots := []string{filepath.Join(os.TempDir(), "nvim."+os.Getenv("USER")), filepath.Join("/tmp", "nvim."+os.Getenv("USER"))}
	if root := os.Getenv("XDG_RUNTIME_DIR"); root != "" {
		roots = append(roots, root, filepath.Join(root, "nvim."+os.Getenv("USER")))
	}
	for _, root := range roots {
		for _, pattern := range []string{filepath.Join(root, "*", fmt.Sprintf("nvim.%d.*", pid)), filepath.Join(root, fmt.Sprintf("nvim.%d.*", pid))} {
			paths, err := filepath.Glob(pattern)
			if err != nil {
				return nil, err
			}
			candidates = append(candidates, paths...)
		}
	}

	return candidates, nil
}
