// Package pibridge submits Commentry notifications to a local Pi extension.
// Conversations and delivery claims remain owned by the inbox backend.
package pibridge

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// Socket names the private receiver for a Rex foreground-process identity.
func Socket(target string) string {
	root := os.Getenv("COMMENTRY_PI_RUNTIME_DIR")
	if root == "" {
		root = fmt.Sprintf("/tmp/commentry-pi-%d", os.Getuid())
	}
	sum := sha256.Sum256([]byte(target))
	return filepath.Join(root, hex.EncodeToString(sum[:12])+".sock")
}

type receipt struct {
	Target    string `json:"target"`
	Session   string `json:"session"`
	Project   string `json:"project"`
	Directory string `json:"directory"`
	Mode      string `json:"mode"`
	Submitted bool   `json:"submitted"`
	Error     string `json:"error"`
}

// Send probes session identity, then submits once through Pi's native API.
// Errors must never cause an automatic terminal fallback: acceptance may be
// uncertain even when the HTTP response was lost.
func Send(ctx context.Context, target, project, directory, text, mode string) error {
	filename := Socket(target)
	info, err := os.Lstat(filepath.Dir(filename))
	if err != nil || !info.IsDir() || info.Mode().Perm()&0o077 != 0 {
		return fmt.Errorf("pi native receiver unavailable; load the Commentry extension or explicitly select terminal delivery")
	}
	transport := &http.Transport{DisableKeepAlives: true, DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", filename)
	}}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 5 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	status, err := call(ctx, client, http.MethodGet, "/status", nil)
	if err != nil {
		return fmt.Errorf("pi receiver unavailable; no terminal fallback: %w", err)
	}
	if status.Target != target || status.Project != project || status.Directory != directory || status.Session == "" {
		return fmt.Errorf("pi receiver identity, project or inbox directory changed; inspect and select the agent again")
	}
	payload := map[string]string{"target": target, "session": status.Session, "project": project, "directory": directory, "text": text, "mode": mode}
	submitted, err := call(ctx, client, http.MethodPost, "/deliver", payload)
	if err != nil {
		return fmt.Errorf("pi submission failed or acceptance is unknown; inspect before notifying again: %w", err)
	}
	if !submitted.Submitted || submitted.Target != target || submitted.Session != status.Session || submitted.Mode != mode {
		return fmt.Errorf("pi receipt missing or mismatched; inspect before notifying again")
	}
	return nil
}

func call(ctx context.Context, client *http.Client, method, path string, input any) (receipt, error) {
	var result receipt
	var body io.Reader
	if input != nil {
		raw, err := json.Marshal(input)
		if err != nil {
			return result, err
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, "http://commentry.local"+path, body)
	if err != nil {
		return result, err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := client.Do(req)
	if err != nil {
		return result, err
	}
	defer func() { _ = res.Body.Close() }()
	if err = json.NewDecoder(io.LimitReader(res.Body, 8192)).Decode(&result); err != nil {
		return result, err
	}
	if res.StatusCode != http.StatusOK || result.Error != "" {
		return result, fmt.Errorf("receiver rejected request: %s", result.Error)
	}
	return result, nil
}
