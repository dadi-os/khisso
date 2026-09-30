package node

import (
	"errors"
	"net/netip"
	"os"
	"path/filepath"
	"testing"

	"tailscale.com/net/tstun"
	"tailscale.com/wgengine/router"
)

func TestValidateNamesTheMissingField(t *testing.T) {
	full := Config{ControlURL: "http://192.0.2.10:8080", Hostname: "mac", StateDir: "/tmp/x"}
	if err := full.Validate(); err != nil {
		t.Fatalf("full config: %v", err)
	}
	cases := map[string]Config{
		"control_url is required": {Hostname: "mac", StateDir: "/tmp/x"},
		"hostname is required":    {ControlURL: "http://c", StateDir: "/tmp/x"},
		"state_dir is required":   {ControlURL: "http://c", Hostname: "mac"},
	}
	for want, cfg := range cases {
		if err := cfg.Validate(); err == nil || err.Error() != want {
			t.Errorf("Validate() = %v, want %q", err, want)
		}
	}
}

func TestStartOptionsSendsAuthKeyOnlyForFirstLogin(t *testing.T) {
	cfg := Config{ControlURL: "http://c", Hostname: "mac", AuthKey: "key", StateDir: "/tmp/x"}

	saved, err := startOptions(cfg, true)
	if err != nil {
		t.Fatal(err)
	}
	if saved.AuthKey != "" {
		t.Errorf("saved node sent auth key %q", saved.AuthKey)
	}
	if saved.UpdatePrefs.ControlURL != "http://c" || saved.UpdatePrefs.Hostname != "mac" || !saved.UpdatePrefs.WantRunning || !saved.UpdatePrefs.CorpDNS {
		t.Errorf("prefs = %+v", saved.UpdatePrefs)
	}

	first, err := startOptions(cfg, false)
	if err != nil {
		t.Fatal(err)
	}
	if first.AuthKey != "key" {
		t.Errorf("first login auth key = %q, want key", first.AuthKey)
	}

	cfg.AuthKey = ""
	if _, err := startOptions(cfg, false); !errors.Is(err, ErrNotProvisioned) {
		t.Errorf("no key and no saved node: err = %v, want ErrNotProvisioned", err)
	}
}

func TestStartWithoutNodeOrKeyIsNotProvisioned(t *testing.T) {
	cfg := Config{ControlURL: "http://127.0.0.1:1", Hostname: "test", StateDir: t.TempDir()}
	_, err := Start(cfg, ExtensionNetwork(tstun.NewFake(), func(RouteSettings) {}), t.Logf, func() {})
	if !errors.Is(err, ErrNotProvisioned) {
		t.Fatalf("Start() err = %v, want ErrNotProvisioned", err)
	}
}

func TestStartRunsAgainstUnreachableControlAndReportsStatus(t *testing.T) {
	dir := t.TempDir()
	cfg := Config{ControlURL: "http://127.0.0.1:1", Hostname: "test", AuthKey: "tskey-test", StateDir: dir}
	changed := make(chan struct{}, 16)
	n, err := Start(cfg, ExtensionNetwork(tstun.NewFake(), func(RouteSettings) {}), t.Logf, func() {
		select {
		case changed <- struct{}{}:
		default:
		}
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	<-changed
	st := n.Status()
	if st.BackendState == "" || st.BackendState == "Running" {
		t.Errorf("BackendState = %q, want a not-running state", st.BackendState)
	}
	if st.Peers == nil {
		t.Error("Peers is nil, want an empty list")
	}
	if _, err := n.StatusJSON(); err != nil {
		t.Errorf("StatusJSON: %v", err)
	}
	n.Stop()
	if _, err := os.Stat(filepath.Join(dir, StateFile)); err != nil {
		t.Errorf("state file not written: %v", err)
	}
}

func TestRouterReportsAddressesAndRoutes(t *testing.T) {
	var got RouteSettings
	r := &extensionRouter{onSet: func(s RouteSettings) { got = s }}
	err := r.Set(&router.Config{
		LocalAddrs: []netip.Prefix{netip.MustParsePrefix("100.64.0.2/32")},
		Routes:     []netip.Prefix{netip.MustParsePrefix("100.64.0.0/10")},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got.LocalAddrs) != 1 || got.LocalAddrs[0] != "100.64.0.2/32" || len(got.Routes) != 1 || got.Routes[0] != "100.64.0.0/10" {
		t.Errorf("RouteSettings = %+v", got)
	}
	if err := r.Set(nil); err != nil || got.LocalAddrs == nil || len(got.LocalAddrs) != 0 {
		t.Errorf("Set(nil) = %v, settings %+v", err, got)
	}
}
