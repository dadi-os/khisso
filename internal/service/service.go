// Package service is dadid's control plane on Windows and Linux: it keeps
// this device's provisioning and on/off choice on disk, runs the node while dadi
// is on, and serves the local API the dadi app uses.
package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/dadi-os/khisso/internal/node"
	"tailscale.com/types/logger"
)

// SettingsFile is the device's saved provisioning and on/off choice inside the
// state directory. It holds the auth key, so it is written 0600.
const SettingsFile = "dadi.json"

// nodeDir is where the node keeps its Tailscale state inside the state directory.
const nodeDir = "node"

// Settings is what the device was provisioned with and whether dadi should run.
type Settings struct {
	ControlURL  string `json:"control_url"`
	NodeName    string `json:"node_name"`
	AuthKey     string `json:"auth_key"`
	WantRunning bool   `json:"want_running"`
}

// Runner is a running node as the service uses it.
type Runner interface {
	Stop()
	Status() node.Status
}

// StartFunc starts a node with cfg.
type StartFunc func(cfg node.Config) (Runner, error)

// Service owns the device's settings and node.
type Service struct {
	stateDir string
	start    StartFunc
	logf     logger.Logf

	mu       sync.Mutex
	settings *Settings
	node     Runner
	lastErr  string
}

// New loads saved settings from stateDir and, when dadi was left on, starts the
// node. A failed start is kept as the last error and shown by /status; the
// service still serves its API so the app can report it.
func New(stateDir string, start StartFunc, logf logger.Logf) (*Service, error) {
	if strings.TrimSpace(stateDir) == "" {
		return nil, errors.New("state dir is required")
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return nil, fmt.Errorf("create state dir: %w", err)
	}
	s := &Service{stateDir: stateDir, start: start, logf: logf}
	saved, err := s.load()
	if err != nil {
		return nil, err
	}
	s.settings = saved
	if saved != nil && saved.WantRunning {
		s.startLocked()
	}
	return s, nil
}

// Close stops the node without changing the saved on/off choice.
func (s *Service) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()
}

// StatusResponse is GET /status.
type StatusResponse struct {
	Provisioned bool         `json:"provisioned"`
	WantRunning bool         `json:"want_running"`
	NodeName    string       `json:"node_name"`
	Node        *node.Status `json:"node"`
	LastError   string       `json:"last_error"`
}

// ProvisionRequest is POST /provision: the fields of a setup code.
type ProvisionRequest struct {
	ControlURL string `json:"control_url"`
	AuthKey    string `json:"auth_key"`
	NodeName   string `json:"node_name"`
}

// Handler serves the local API.
func (s *Service) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /status", func(w http.ResponseWriter, r *http.Request) {
		s.writeJSON(w, http.StatusOK, s.status())
	})
	mux.HandleFunc("POST /provision", func(w http.ResponseWriter, r *http.Request) {
		var req ProvisionRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			s.writeError(w, http.StatusUnprocessableEntity, "invalid_request", "body is not a provisioning request: "+err.Error())
			return
		}
		if err := s.provision(req); err != nil {
			s.writeServiceError(w, err)
			return
		}
		s.writeJSON(w, http.StatusOK, s.status())
	})
	mux.HandleFunc("POST /up", func(w http.ResponseWriter, r *http.Request) {
		if err := s.setWantRunning(true); err != nil {
			s.writeServiceError(w, err)
			return
		}
		s.writeJSON(w, http.StatusOK, s.status())
	})
	mux.HandleFunc("POST /down", func(w http.ResponseWriter, r *http.Request) {
		if err := s.setWantRunning(false); err != nil {
			s.writeServiceError(w, err)
			return
		}
		s.writeJSON(w, http.StatusOK, s.status())
	})
	mux.HandleFunc("POST /forget", func(w http.ResponseWriter, r *http.Request) {
		if err := s.forget(); err != nil {
			s.writeServiceError(w, err)
			return
		}
		s.writeJSON(w, http.StatusOK, s.status())
	})
	return mux
}

// errNotProvisioned is returned by /up before any setup code was given.
var errNotProvisioned = errors.New("this device is not provisioned")

// invalidRequest marks a request the caller must fix.
type invalidRequest struct{ msg string }

func (e invalidRequest) Error() string { return e.msg }

func (s *Service) status() StatusResponse {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := StatusResponse{LastError: s.lastErr}
	if s.settings != nil {
		out.Provisioned = true
		out.WantRunning = s.settings.WantRunning
		out.NodeName = s.settings.NodeName
	}
	if s.node != nil {
		st := s.node.Status()
		out.Node = &st
	}
	return out
}

// provision replaces the device's settings with a new setup code and a fresh
// node identity, and turns dadi on.
func (s *Service) provision(req ProvisionRequest) error {
	switch {
	case strings.TrimSpace(req.ControlURL) == "":
		return invalidRequest{"control_url is required"}
	case strings.TrimSpace(req.AuthKey) == "":
		return invalidRequest{"auth_key is required"}
	case strings.TrimSpace(req.NodeName) == "":
		return invalidRequest{"node_name is required"}
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()
	if err := os.RemoveAll(filepath.Join(s.stateDir, nodeDir)); err != nil {
		return fmt.Errorf("clear previous node: %w", err)
	}
	next := &Settings{ControlURL: req.ControlURL, NodeName: req.NodeName, AuthKey: req.AuthKey, WantRunning: true}
	if err := s.save(next); err != nil {
		return err
	}
	s.settings = next
	s.startLocked()
	return nil
}

func (s *Service) setWantRunning(want bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.settings == nil {
		return errNotProvisioned
	}
	next := *s.settings
	next.WantRunning = want
	if err := s.save(&next); err != nil {
		return err
	}
	s.settings = &next
	if want && s.node == nil {
		s.startLocked()
	}
	if !want {
		s.stopLocked()
		s.lastErr = ""
	}
	return nil
}

// forget stops dadi and deletes the device's settings and node identity.
func (s *Service) forget() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopLocked()
	for _, p := range []string{filepath.Join(s.stateDir, SettingsFile), filepath.Join(s.stateDir, nodeDir)} {
		if err := os.RemoveAll(p); err != nil {
			return fmt.Errorf("remove %s: %w", filepath.Base(p), err)
		}
	}
	s.settings = nil
	s.lastErr = ""
	return nil
}

func (s *Service) startLocked() {
	n, err := s.start(node.Config{
		ControlURL: s.settings.ControlURL,
		Hostname:   s.settings.NodeName,
		AuthKey:    s.settings.AuthKey,
		StateDir:   filepath.Join(s.stateDir, nodeDir),
	})
	if err != nil {
		s.lastErr = err.Error()
		return
	}
	s.node = n
	s.lastErr = ""
}

func (s *Service) stopLocked() {
	if s.node != nil {
		s.node.Stop()
		s.node = nil
	}
}

func (s *Service) load() (*Settings, error) {
	b, err := os.ReadFile(filepath.Join(s.stateDir, SettingsFile))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read settings: %w", err)
	}
	var saved Settings
	if err := json.Unmarshal(b, &saved); err != nil {
		return nil, fmt.Errorf("parse settings: %w", err)
	}
	return &saved, nil
}

func (s *Service) save(settings *Settings) error {
	b, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return err
	}
	path := filepath.Join(s.stateDir, SettingsFile)
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return fmt.Errorf("write settings: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		return fmt.Errorf("save settings: %w", err)
	}
	return nil
}

func (s *Service) writeServiceError(w http.ResponseWriter, err error) {
	var invalid invalidRequest
	switch {
	case errors.As(err, &invalid):
		s.writeError(w, http.StatusUnprocessableEntity, "invalid_request", err.Error())
	case errors.Is(err, errNotProvisioned):
		s.writeError(w, http.StatusConflict, "not_provisioned", err.Error())
	default:
		s.writeError(w, http.StatusInternalServerError, "internal_error", err.Error())
	}
}

func (s *Service) writeError(w http.ResponseWriter, status int, code, msg string) {
	s.writeJSON(w, status, map[string]any{"error": map[string]string{"type": code, "message": msg}})
}

func (s *Service) writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		s.logf("write response: %v", err)
	}
}
