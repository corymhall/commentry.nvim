// Package executor connects the local Commentry client to its Executor app.
package executor

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Config identifies the hosted app. Tokens are kept in a separate private file.
type Config struct {
	URL          string `json:"url"`
	Organization string `json:"organization"`
	App          string `json:"app"`
}

// Client invokes authenticated app operations without replaying failed calls.
type Client struct {
	Config    Config
	Directory string
}

// Open reads an explicitly configured Executor destination. A missing config
// returns [os.ErrNotExist] so the caller can support a legacy local export.
func Open(directory string) (*Client, error) {
	// #nosec G304 -- The caller selects the Commentry configuration directory.
	data, err := os.ReadFile(filepath.Join(directory, "executor.json"))
	if err != nil {
		return nil, err
	}
	var config Config
	if err = json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("read Executor configuration: %w", err)
	}
	if err = config.validate(); err != nil {
		return nil, err
	}
	return &Client{Config: config, Directory: directory}, nil
}

func (c Config) validate() error {
	u, err := url.Parse(c.URL)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || strings.Trim(u.Path, "/") != "" {
		return fmt.Errorf("executor URL must be an origin")
	}
	loopback := u.Hostname() == "127.0.0.1" || u.Hostname() == "localhost" || u.Hostname() == "::1"
	if u.Scheme != "https" && (u.Scheme != "http" || !loopback) {
		return fmt.Errorf("executor requires HTTPS, except for loopback tests")
	}
	if c.Organization == "" || c.App == "" {
		return fmt.Errorf("executor organization and app are required")
	}
	return nil
}

// SaveConfig atomically selects the remote app after authentication passes.
func SaveConfig(directory string, config Config) error {
	if err := config.validate(); err != nil {
		return err
	}
	return writeJSON(directory, "executor.json", config)
}

func writeJSON(directory, name string, value any) error {
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	file, err := os.CreateTemp(directory, ".executor-*")
	if err != nil {
		return err
	}
	filename := file.Name()
	defer func() { _ = os.Remove(filename) }()
	if err = file.Chmod(0o600); err == nil {
		_, err = file.Write(data)
	}
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(filename, filepath.Join(directory, name))
}

// Call executes one app tool. Failed mutations are never replayed.
func (c *Client) Call(ctx context.Context, tool string, input, result any) error {
	token, err := c.accessToken(ctx)
	if err != nil {
		return err
	}
	body, err := json.Marshal(map[string]any{"tool": tool, "input": input})
	if err != nil {
		return err
	}
	endpoint := strings.TrimRight(c.Config.URL, "/") + "/api/organizations/" + url.PathEscape(c.Config.Organization) + "/apps/" + url.PathEscape(c.Config.App) + "/tools/call"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	client := http.Client{Timeout: 30 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("executor call failed; inspect before retrying a write: %w", err)
	}
	return toolResponse(response, tool, result)
}

func toolResponse(response *http.Response, tool string, result any) error {
	defer func() { _ = response.Body.Close() }()
	raw, err := io.ReadAll(io.LimitReader(response.Body, 16*1024*1024+1))
	if err != nil {
		return fmt.Errorf("executor response interrupted; inspect before retrying: %w", err)
	}
	if len(raw) > 16*1024*1024 {
		return fmt.Errorf("executor response exceeds 16 MiB")
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		if response.StatusCode == http.StatusUnauthorized {
			return fmt.Errorf("executor sign-in expired; run commentry executor login")
		}
		var failure struct {
			Message string `json:"message"`
			Error   struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.Unmarshal(raw, &failure)
		message := failure.Message
		if message == "" {
			message = failure.Error.Message
		}
		if message == "" {
			message = http.StatusText(response.StatusCode)
		}
		return fmt.Errorf("executor %s failed with status %d: %s", tool, response.StatusCode, message)
	}
	if result == nil {
		return nil
	}
	if err = json.Unmarshal(raw, result); err != nil {
		return fmt.Errorf("invalid Executor response; inspect before retrying a write: %w", err)
	}
	return nil
}

func decodeResponse(response *http.Response, result any) error {
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("executor authorization returned HTTP %d", response.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(response.Body, 1024*1024)).Decode(result)
}

// IsUnconfigured distinguishes a legacy store from an unusable configuration.
func IsUnconfigured(err error) bool { return errors.Is(err, os.ErrNotExist) }
