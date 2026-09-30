// Package node runs dadi's Tailscale node. The same node runs inside an Apple
// packet-tunnel extension, where the OS owns the tunnel, routes and DNS, and as
// a system service on Windows and Linux, where it creates the tunnel and
// configures routes and DNS itself.
package node

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/tailscale/wireguard-go/tun"
	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnlocal"
	"tailscale.com/ipn/store"
	"tailscale.com/net/dns"
	"tailscale.com/net/netmon"
	"tailscale.com/net/tsdial"
	"tailscale.com/net/tstun"
	"tailscale.com/tsd"
	"tailscale.com/types/logger"
	"tailscale.com/types/logid"
	"tailscale.com/wgengine"
	"tailscale.com/wgengine/router"
)

// StateFile is the Tailscale state file name inside Config.StateDir. It uses the
// same format as tailscaled's, so a daemon's state file can be moved in as is.
const StateFile = "tailscaled.state"

// ErrNotProvisioned means there is no saved node identity and no auth key to
// create one; the device needs a setup code.
var ErrNotProvisioned = errors.New("not provisioned: no saved node and no auth key")

// Config is what the extension passes to Start. ControlURL, Hostname and
// StateDir are required; AuthKey is used only when no node is saved yet.
type Config struct {
	ControlURL string `json:"control_url"`
	Hostname   string `json:"hostname"`
	AuthKey    string `json:"auth_key"`
	StateDir   string `json:"state_dir"`
}

// Validate reports the first missing required field.
func (c Config) Validate() error {
	switch {
	case strings.TrimSpace(c.ControlURL) == "":
		return errors.New("control_url is required")
	case strings.TrimSpace(c.Hostname) == "":
		return errors.New("hostname is required")
	case strings.TrimSpace(c.StateDir) == "":
		return errors.New("state_dir is required")
	}
	return nil
}

// RouteSettings is the tunnel configuration the node wants applied: its own
// addresses and the routes that belong inside the tunnel.
type RouteSettings struct {
	LocalAddrs []string `json:"local_addrs"`
	Routes     []string `json:"routes"`
}

// Peer is one other device on dadi as the app shows it.
type Peer struct {
	Name   string `json:"name"`
	IP     string `json:"ip"`
	Online bool   `json:"online"`
}

// Status is the node's state as the app shows it.
type Status struct {
	BackendState string `json:"backend_state"`
	Hostname     string `json:"hostname"`
	SelfIP       string `json:"self_ip"`
	Peers        []Peer `json:"peers"`
	LastError    string `json:"last_error"`
}

// Network is the tunnel device and the OS integration the engine drives.
type Network struct {
	Tun    tun.Device
	Router router.Router
	// DNS configures the OS resolver; nil leaves it to the caller, as in an
	// extension whose DNS settings the OS applies.
	DNS dns.OSConfigurator
}

// NetworkFunc builds the Network once the node's network monitor and
// subsystems exist. Start calls it exactly once.
type NetworkFunc func(logf logger.Logf, netMon *netmon.Monitor, sys *tsd.System) (Network, error)

// ExtensionNetwork runs on a packet-tunnel extension's utun device. The OS owns
// routes and DNS, so the engine's tunnel configuration goes to onRoutes.
func ExtensionNetwork(dev tun.Device, onRoutes func(RouteSettings)) NetworkFunc {
	return func(logger.Logf, *netmon.Monitor, *tsd.System) (Network, error) {
		return Network{Tun: dev, Router: &extensionRouter{onSet: onRoutes}}, nil
	}
}

// SystemNetwork creates the tunnel interface tunName and configures the OS's
// routes and DNS for it. It needs administrator rights (Windows) or root (Linux).
func SystemNetwork(tunName string) NetworkFunc {
	return func(logf logger.Logf, netMon *netmon.Monitor, sys *tsd.System) (Network, error) {
		dev, devName, err := tstun.New(logf, tunName)
		if err != nil {
			return Network{}, fmt.Errorf("create tunnel %q: %w", tunName, err)
		}
		r, err := router.New(logf, dev, netMon, sys.HealthTracker())
		if err != nil {
			dev.Close()
			return Network{}, fmt.Errorf("router: %w", err)
		}
		d, err := dns.NewOSConfigurator(logf, sys.HealthTracker(), sys.ControlKnobs(), devName)
		if err != nil {
			r.Close()
			dev.Close()
			return Network{}, fmt.Errorf("dns configurator: %w", err)
		}
		return Network{Tun: dev, Router: r, DNS: d}, nil
	}
}

// Node is a running Tailscale node. Create it with Start and end it with Stop.
type Node struct {
	lb     *ipnlocal.LocalBackend
	cancel context.CancelFunc
	done   chan struct{}

	mu        sync.Mutex
	lastError string
}

// Start brings up a node with cfg on the network that network builds. onChange
// fires when the state, the peers or the last error change. network is called
// after cfg is validated and the state directory exists; from then on the node
// owns what it returns.
func Start(cfg Config, network NetworkFunc, logf logger.Logf, onChange func()) (*Node, error) {
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(cfg.StateDir, 0o700); err != nil {
		return nil, fmt.Errorf("create state dir: %w", err)
	}

	sys := new(tsd.System)
	netMon, err := netmon.New(logf)
	if err != nil {
		return nil, fmt.Errorf("netmon: %w", err)
	}
	sys.Set(netMon)
	sys.Set(&tsdial.Dialer{Logf: logf})
	sys.HealthTracker().SetMetricsRegistry(sys.UserMetricsRegistry())

	net, err := network(logf, netMon, sys)
	if err != nil {
		netMon.Close()
		return nil, err
	}
	sys.Set(net.Router)
	engine, err := wgengine.NewUserspaceEngine(logf, wgengine.Config{
		Tun:           net.Tun,
		Router:        net.Router,
		DNS:           net.DNS,
		NetMon:        netMon,
		HealthTracker: sys.HealthTracker(),
		Metrics:       sys.UserMetricsRegistry(),
		Dialer:        sys.Dialer.Get(),
		SetSubsystem:  sys.Set,
		ControlKnobs:  sys.ControlKnobs(),
	})
	if err != nil {
		netMon.Close()
		return nil, fmt.Errorf("engine: %w", err)
	}
	sys.Set(wgengine.NewWatchdog(engine))
	sys.NetstackRouter.Set(false)

	st, err := store.New(logf, filepath.Join(cfg.StateDir, StateFile))
	if err != nil {
		engine.Close()
		return nil, fmt.Errorf("state store: %w", err)
	}
	sys.Set(st)
	if w, ok := sys.Tun.GetOK(); ok {
		w.Start()
	}

	lb, err := ipnlocal.NewLocalBackend(logf, logid.PublicID{}, sys, 0)
	if err != nil {
		engine.Close()
		return nil, fmt.Errorf("local backend: %w", err)
	}
	lb.SetVarRoot(cfg.StateDir)

	opts, err := startOptions(cfg, lb.CurrentProfile().ID() != "")
	if err != nil {
		lb.Shutdown()
		return nil, err
	}

	ctx, cancel := context.WithCancel(context.Background())
	n := &Node{lb: lb, cancel: cancel, done: make(chan struct{})}
	watching := make(chan struct{})
	go func() {
		defer close(n.done)
		lb.WatchNotifications(ctx, ipn.NotifyInitialState, func() { close(watching) }, func(msg *ipn.Notify) bool {
			if msg.ErrMessage != nil {
				n.mu.Lock()
				n.lastError = *msg.ErrMessage
				n.mu.Unlock()
			}
			if msg.State != nil || msg.NetMap != nil || msg.ErrMessage != nil {
				onChange()
			}
			return true
		})
	}()
	<-watching

	if err := lb.Start(opts); err != nil {
		n.Stop()
		return nil, fmt.Errorf("start: %w", err)
	}
	return n, nil
}

// startOptions builds the start request. The auth key is sent only when there
// is no saved node, so a restart never re-registers with an expired key.
func startOptions(cfg Config, hasSavedNode bool) (ipn.Options, error) {
	prefs := ipn.NewPrefs()
	prefs.ControlURL = cfg.ControlURL
	prefs.Hostname = cfg.Hostname
	prefs.WantRunning = true
	prefs.CorpDNS = true
	prefs.RouteAll = false
	opts := ipn.Options{UpdatePrefs: prefs}
	if hasSavedNode {
		return opts, nil
	}
	if strings.TrimSpace(cfg.AuthKey) == "" {
		return ipn.Options{}, ErrNotProvisioned
	}
	opts.AuthKey = cfg.AuthKey
	return opts, nil
}

// Stop shuts the node down and releases the tunnel device.
func (n *Node) Stop() {
	n.cancel()
	n.lb.Shutdown()
	<-n.done
}

// Status reports the node's current state, self address and peers.
func (n *Node) Status() Status {
	st := n.lb.Status()
	out := Status{BackendState: st.BackendState, Peers: []Peer{}}
	if st.Self != nil {
		out.Hostname = st.Self.HostName
		if len(st.Self.TailscaleIPs) > 0 {
			out.SelfIP = st.Self.TailscaleIPs[0].String()
		}
	}
	for _, p := range st.Peer {
		peer := Peer{Name: p.HostName, Online: p.Online}
		if len(p.TailscaleIPs) > 0 {
			peer.IP = p.TailscaleIPs[0].String()
		}
		out.Peers = append(out.Peers, peer)
	}
	n.mu.Lock()
	out.LastError = n.lastError
	n.mu.Unlock()
	return out
}

// StatusJSON is Status encoded for the extension and the app.
func (n *Node) StatusJSON() ([]byte, error) {
	return json.Marshal(n.Status())
}

// extensionRouter hands the engine's tunnel configuration to the extension,
// which applies it with NEPacketTunnelNetworkSettings.
type extensionRouter struct {
	onSet func(RouteSettings)
}

func (r *extensionRouter) Up() error { return nil }

func (r *extensionRouter) Set(cfg *router.Config) error {
	if cfg == nil {
		r.onSet(RouteSettings{LocalAddrs: []string{}, Routes: []string{}})
		return nil
	}
	r.onSet(RouteSettings{LocalAddrs: prefixStrings(cfg.LocalAddrs), Routes: prefixStrings(cfg.Routes)})
	return nil
}

func (r *extensionRouter) UpdateMagicsockPort(uint16, string) error { return nil }

func (r *extensionRouter) Close() error { return nil }

func prefixStrings(prefixes []netip.Prefix) []string {
	out := make([]string, 0, len(prefixes))
	for _, p := range prefixes {
		out = append(out, p.String())
	}
	return out
}
