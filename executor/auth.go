package executor

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

type rateLimitError struct{ delay time.Duration }

func (e *rateLimitError) Error() string {
	return "executor authorization is rate-limited; retry after the indicated delay"
}

type pendingState struct {
	Grant    DeviceLogin `json:"grant"`
	Client   string      `json:"client"`
	Token    string      `json:"token"`
	Resource string      `json:"resource"`
	Deadline int64       `json:"deadline"`
}

type metadata struct {
	Issuer       string `json:"issuer"`
	Registration string `json:"registration_endpoint"`
	Device       string `json:"device_authorization_endpoint"`
	Token        string `json:"token_endpoint"`
}
type session struct {
	Client        string `json:"client_id"`
	Access        string `json:"access_token"`
	Refresh       string `json:"refresh_token"`
	Expires       int64  `json:"expires_at"`
	TokenEndpoint string `json:"token_endpoint"`
	Resource      string `json:"resource"`
}
type tokenResponse struct {
	Access  string `json:"access_token"`
	Refresh string `json:"refresh_token"`
	Expires int64  `json:"expires_in"`
	Error   string `json:"error"`
}

// DeviceLogin is a pending browser authorization. DeviceCode stays private.
type DeviceLogin struct {
	Error       string `json:"error"`
	URL         string `json:"verification_uri"`
	CompleteURL string `json:"verification_uri_complete"`
	Code        string `json:"user_code"`
	DeviceCode  string `json:"device_code"`
	Interval    int    `json:"interval"`
	Expires     int    `json:"expires_in"`
	client      string
	token       string
	resource    string
}

func authHTTP() *http.Client {
	return &http.Client{Timeout: 15 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
}

func authPost(ctx context.Context, endpoint string, form url.Values, result any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := authHTTP().Do(req)
	if err != nil {
		return err
	}
	if response.StatusCode == http.StatusTooManyRequests {
		_ = response.Body.Close()
		seconds, _ := strconv.Atoi(response.Header.Get("Retry-After"))
		return &rateLimitError{delay: time.Duration(max(seconds, 60)) * time.Second}
	}
	// OAuth pending and slow_down use HTTP 400 with a structured error.
	if response.StatusCode == http.StatusBadRequest {
		defer func() { _ = response.Body.Close() }()
		return json.NewDecoder(response.Body).Decode(result)
	}
	return decodeResponse(response, result)
}

func discover(ctx context.Context, origin string) (metadata, error) {
	var m metadata
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(origin, "/")+"/.well-known/oauth-authorization-server", nil)
	if err != nil {
		return m, err
	}
	response, err := authHTTP().Do(req)
	if err != nil {
		return m, err
	}
	if err = decodeResponse(response, &m); err != nil {
		return m, err
	}
	base, _ := url.Parse(origin)
	for _, endpoint := range []string{m.Issuer, m.Registration, m.Device, m.Token} {
		u, parseErr := url.Parse(endpoint)
		if parseErr != nil || u.Scheme != base.Scheme || u.Host != base.Host || u.User != nil || u.Fragment != "" {
			return m, fmt.Errorf("executor authorization metadata has an unsupported endpoint")
		}
	}
	return m, nil
}

// BeginLogin starts Executor's device flow without reading other credentials.
func BeginLogin(ctx context.Context, directory string, config Config) (DeviceLogin, error) {
	var pending DeviceLogin
	if err := config.validate(); err != nil {
		return pending, err
	}
	m, err := discover(ctx, config.URL)
	if err != nil {
		return pending, err
	}
	if resumed, found, readErr := resumePending(directory, m.Token); readErr != nil {
		return pending, readErr
	} else if found {
		return resumed, nil
	}
	client, err := registeredClient(ctx, directory, config.URL, m.Registration)
	if err != nil {
		return pending, err
	}
	if err = authPost(ctx, m.Device, url.Values{"client_id": {client}, "scope": {"executor offline_access"}, "resource": {strings.TrimRight(config.URL, "/") + "/api"}}, &pending); err != nil {
		return pending, err
	}
	if pending.DeviceCode == "" || pending.URL == "" || pending.Expires <= 0 {
		return pending, fmt.Errorf("executor did not issue a device authorization: %s", pending.Error)
	}
	pending.client, pending.token = client, m.Token
	pending.resource = strings.TrimRight(config.URL, "/") + "/api"
	if err = writeJSON(directory, "executor-pending.json", pendingState{Grant: pending, Client: pending.client, Token: pending.token, Resource: pending.resource, Deadline: time.Now().Unix() + int64(pending.Expires)}); err != nil {
		return pending, err
	}
	return pending, nil
}

func resumePending(directory, token string) (DeviceLogin, bool, error) {
	// #nosec G304 -- Resume only the private request created by this login flow.
	raw, err := os.ReadFile(filepath.Join(directory, "executor-pending.json"))
	if os.IsNotExist(err) {
		return DeviceLogin{}, false, nil
	}
	if err != nil {
		return DeviceLogin{}, false, err
	}
	var saved pendingState
	if err = json.Unmarshal(raw, &saved); err != nil {
		return DeviceLogin{}, false, err
	}
	if saved.Token != token || saved.Deadline <= time.Now().Unix() {
		return DeviceLogin{}, false, nil
	}
	pending := saved.Grant
	pending.client, pending.token, pending.resource = saved.Client, saved.Token, saved.Resource
	pending.Expires = int(saved.Deadline - time.Now().Unix())
	return pending, true, nil
}

// CompleteLogin polls only the pending device request, then saves its session.
// It never approves the request. The user must approve in their browser.
func CompleteLogin(ctx context.Context, directory string, pending DeviceLogin) error {
	token, err := pollDevice(ctx, pending)
	if err != nil {
		return err
	}
	if token.Access == "" {
		return fmt.Errorf("executor authorization omitted its access token")
	}
	if err = writeJSON(directory, "executor-session.json", session{Client: pending.client, Access: token.Access, Refresh: token.Refresh, Expires: time.Now().Unix() + token.Expires, TokenEndpoint: pending.token, Resource: pending.resource}); err != nil {
		return err
	}
	if err = os.Remove(filepath.Join(directory, "executor-pending.json")); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func pollDevice(ctx context.Context, pending DeviceLogin) (tokenResponse, error) {
	ctx, cancel := context.WithTimeout(ctx, time.Duration(pending.Expires)*time.Second)
	defer cancel()
	interval := time.Duration(max(pending.Interval, 5)) * time.Second
	for {
		select {
		case <-ctx.Done():
			return tokenResponse{}, ctx.Err()
		case <-time.After(interval):
		}
		token, delay, err := exchangeDevice(ctx, pending)
		if err != nil {
			return token, err
		}
		if delay > 0 {
			interval = max(interval, delay)
			continue
		}
		return token, nil
	}
}

func exchangeDevice(ctx context.Context, pending DeviceLogin) (tokenResponse, time.Duration, error) {
	var token tokenResponse
	err := authPost(ctx, pending.token, url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:device_code"}, "device_code": {pending.DeviceCode}, "client_id": {pending.client}, "resource": {pending.resource}}, &token)
	if rate, ok := errors.AsType[*rateLimitError](err); ok {
		return token, rate.delay, nil
	}
	if err != nil {
		return token, 0, err
	}
	switch token.Error {
	case "authorization_pending":
		return token, 5 * time.Second, nil
	case "slow_down":
		return token, 60 * time.Second, nil
	case "":
		return token, 0, nil
	default:
		return token, 0, fmt.Errorf("executor authorization was not completed: %s", token.Error)
	}
}

func (c *Client) accessToken(ctx context.Context) (string, error) {
	// Serialize refresh-token rotation across short-lived CLI processes. flock
	// releases on process exit, including a crash while refreshing a session.
	// #nosec G304 -- The lock is in the selected Commentry configuration directory.
	lock, err := os.OpenFile(filepath.Join(c.Directory, ".executor.lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return "", err
	}
	defer func() { _ = lock.Close() }()
	for {
		err = unix.Flock(int(lock.Fd()), unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			break
		}
		if err != unix.EWOULDBLOCK {
			return "", err
		}
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-time.After(25 * time.Millisecond):
		}
	}
	defer func() { _ = unix.Flock(int(lock.Fd()), unix.LOCK_UN) }()
	return c.readAccessToken(ctx)
}

func (c *Client) readAccessToken(ctx context.Context) (string, error) {
	// #nosec G304 -- This is the session created by Commentry's own login flow.
	data, err := os.ReadFile(filepath.Join(c.Directory, "executor-session.json"))
	if err != nil {
		return "", fmt.Errorf("sign in with commentry executor login: %w", err)
	}
	var s session
	if err = json.Unmarshal(data, &s); err != nil {
		return "", err
	}
	endpoint, err := url.Parse(s.TokenEndpoint)
	origin, _ := url.Parse(c.Config.URL)
	if err != nil || endpoint.Scheme != origin.Scheme || endpoint.Host != origin.Host {
		return "", fmt.Errorf("executor session belongs to a different host; sign in again")
	}
	if s.Access != "" && time.Now().Unix()+30 < s.Expires {
		return s.Access, nil
	}
	if s.Refresh == "" {
		return "", fmt.Errorf("executor sign-in expired; run commentry executor login")
	}
	var token tokenResponse
	if err = authPost(ctx, s.TokenEndpoint, url.Values{"grant_type": {"refresh_token"}, "refresh_token": {s.Refresh}, "client_id": {s.Client}, "resource": {s.Resource}}, &token); err != nil {
		return "", err
	}
	if token.Error != "" || token.Access == "" {
		return "", fmt.Errorf("executor sign-in could not be refreshed; run commentry executor login")
	}
	s.Access, s.Expires = token.Access, time.Now().Unix()+token.Expires
	if token.Refresh != "" {
		s.Refresh = token.Refresh
	}
	if err = writeJSON(c.Directory, "executor-session.json", s); err != nil {
		return "", err
	}
	return s.Access, nil
}

func registeredClient(ctx context.Context, directory, origin, endpoint string) (string, error) {
	var cached struct {
		Origin string `json:"origin"`
		Client string `json:"client_id"`
	}
	// #nosec G304 -- Public registration metadata created by this login flow.
	data, err := os.ReadFile(filepath.Join(directory, "executor-client.json"))
	if err == nil {
		if err = json.Unmarshal(data, &cached); err != nil {
			return "", err
		}
		if cached.Origin == origin && cached.Client != "" {
			return cached.Client, nil
		}
	} else if !os.IsNotExist(err) {
		return "", err
	}
	registration := `{"client_name":"Commentry CLI","grant_types":["urn:ietf:params:oauth:grant-type:device_code","refresh_token"],"response_types":[],"redirect_uris":["http://127.0.0.1/callback"],"token_endpoint_auth_method":"none","scope":"executor offline_access"}`
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(registration))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	response, err := authHTTP().Do(req)
	if err != nil {
		return "", err
	}
	if err = decodeResponse(response, &cached); err != nil {
		return "", err
	}
	if cached.Client == "" {
		return "", fmt.Errorf("executor registration omitted its client ID")
	}
	cached.Origin = origin
	if err = writeJSON(directory, "executor-client.json", cached); err != nil {
		return "", err
	}
	return cached.Client, nil
}
