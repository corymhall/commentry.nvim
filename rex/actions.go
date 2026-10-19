package rex

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// Do invokes a configured Rex action with JSON on stdin. It never starts a
// server or terminal and never passes message text through a shell.
func Do(ctx context.Context, action string, args, result any) error {
	binary, err := executable()
	if err != nil {
		return err
	}
	raw, err := json.Marshal(args)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	// #nosec G204 -- The executable is the selected Rex CLI and arguments are separate.
	command := exec.CommandContext(ctx, binary, "--autostart=false", "do", action, "--args", "-", "--json")
	command.Stdin = strings.NewReader(string(raw))
	output, err := command.Output()
	if err != nil {
		detail := ""
		if exit, ok := err.(*exec.ExitError); ok {
			detail = strings.TrimSpace(string(exit.Stderr))
		}
		return fmt.Errorf("rex do %s: %w %s", action, err, detail)
	}
	if result == nil {
		return nil
	}
	if err = json.Unmarshal(output, result); err != nil {
		return fmt.Errorf("invalid response from rex do %s: %w", action, err)
	}
	return nil
}
