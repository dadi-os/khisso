package service

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dadi-os/khisso/internal/node"
)

type fakeNode struct{ stopped bool }

func (f *fakeNode) Stop()               { f.stopped = true }
func (f *fakeNode) Status() node.Status { return node.Status{BackendState: "Running", Peers: []node.Peer{}} }

// starter records every node config the service starts and can be told to fail.
type starter struct {
	configs []node.Config
	nodes   []*fakeNode
	err     error
}

func (s *starter) start(cfg node.Config) (Runner, error) {
	s.configs = append(s.configs, cfg)
	if s.err != nil {
		return nil, s.err
	}
	n := &fakeNode{}
	s.nodes = append(s.nodes, n)
	return n, nil
}

func call(t *testing.T, h http.Handler, method, path, body string) (int, map[string]any) {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, strings.NewReader(body)))
	var out map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatalf("%s %s: body %q: %v", method, path, rec.Body.String(), err)
	}
	return rec.Code, out
}

func errorType(body map[string]any) string {
	e, _ := body["error"].(map[string]any)
	s, _ := e["type"].(string)
	return s
}

const setupCode = `{"control_url":"http://192.0.2.10:8080","auth_key":"key","node_name":"laptop"}`

func TestUpBeforeProvisioningIsConflict(t *testing.T) {
	st := &starter{}
	svc, err := New(t.TempDir(), st.start, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	code, body := call(t, svc.Handler(), "POST", "/up", "")
	if code != http.StatusConflict || errorType(body) != "not_provisioned" {
		t.Fatalf("POST /up = %d %v, want 409 not_provisioned", code, body)
	}
	if len(st.configs) != 0 {
		t.Errorf("started %d nodes before provisioning", len(st.configs))
	}
}

func TestProvisionValidatesTheSetupCode(t *testing.T) {
	svc, err := New(t.TempDir(), (&starter{}).start, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	code, body := call(t, svc.Handler(), "POST", "/provision", `{"control_url":"http://c","auth_key":"k"}`)
	if code != http.StatusUnprocessableEntity || errorType(body) != "invalid_request" {
		t.Fatalf("POST /provision = %d %v, want 422 invalid_request", code, body)
	}
}

func TestProvisionStartsTheNodeAndSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	st := &starter{}
	svc, err := New(dir, st.start, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	code, body := call(t, svc.Handler(), "POST", "/provision", setupCode)
	if code != http.StatusOK || body["provisioned"] != true || body["want_running"] != true {
		t.Fatalf("POST /provision = %d %v", code, body)
	}
	if len(st.configs) != 1 || st.configs[0].Hostname != "laptop" || st.configs[0].StateDir != filepath.Join(dir, nodeDir) {
		t.Fatalf("started with %+v", st.configs)
	}
	info, err := os.Stat(filepath.Join(dir, SettingsFile))
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("settings file: %v, mode %v", err, info.Mode().Perm())
	}
	svc.Close()

	restarted := &starter{}
	if _, err := New(dir, restarted.start, t.Logf); err != nil {
		t.Fatal(err)
	}
	if len(restarted.configs) != 1 || restarted.configs[0].AuthKey != "key" {
		t.Fatalf("restart started %+v, want the saved node", restarted.configs)
	}
}

func TestDownStopsTheNodeAndStaysDownAfterRestart(t *testing.T) {
	dir := t.TempDir()
	st := &starter{}
	svc, err := New(dir, st.start, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	call(t, svc.Handler(), "POST", "/provision", setupCode)
	code, body := call(t, svc.Handler(), "POST", "/down", "")
	if code != http.StatusOK || body["want_running"] != false || body["node"] != nil {
		t.Fatalf("POST /down = %d %v", code, body)
	}
	if !st.nodes[0].stopped {
		t.Error("node was not stopped")
	}

	restarted := &starter{}
	if _, err := New(dir, restarted.start, t.Logf); err != nil {
		t.Fatal(err)
	}
	if len(restarted.configs) != 0 {
		t.Errorf("restart started a node while dadi is off")
	}
}

func TestFailedStartIsReportedNotHidden(t *testing.T) {
	st := &starter{err: errors.New("create tunnel \"dadi\": access denied")}
	svc, err := New(t.TempDir(), st.start, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	code, body := call(t, svc.Handler(), "POST", "/provision", setupCode)
	if code != http.StatusOK || body["node"] != nil || !strings.Contains(body["last_error"].(string), "access denied") {
		t.Fatalf("POST /provision = %d %v, want the start error in last_error", code, body)
	}
}

func TestForgetRemovesSettingsAndNode(t *testing.T) {
	dir := t.TempDir()
	st := &starter{}
	svc, err := New(dir, st.start, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	call(t, svc.Handler(), "POST", "/provision", setupCode)
	if err := os.MkdirAll(filepath.Join(dir, nodeDir), 0o700); err != nil {
		t.Fatal(err)
	}
	code, body := call(t, svc.Handler(), "POST", "/forget", "")
	if code != http.StatusOK || body["provisioned"] != false {
		t.Fatalf("POST /forget = %d %v", code, body)
	}
	for _, name := range []string{SettingsFile, nodeDir} {
		if _, err := os.Stat(filepath.Join(dir, name)); !errors.Is(err, os.ErrNotExist) {
			t.Errorf("%s still exists after forget", name)
		}
	}
}
