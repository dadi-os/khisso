// Package inapp runs dadi's node inside the app process with userspace
// networking, for builds that have no packet-tunnel extension. Only the app's
// own traffic reaches dadi: it connects through a CONNECT proxy on 127.0.0.1
// that dials over the tailnet and resolves *.dadi names through MagicDNS.
package inapp

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/dadi-os/khisso/internal/node"
	"golang.org/x/net/dns/dnsmessage"
	"tailscale.com/client/local"
	"tailscale.com/ipn"
	"tailscale.com/tsnet"
	"tailscale.com/types/logger"
)

// meshPrefix is the address range Headscale assigns to dadi devices.
var meshPrefix = netip.MustParsePrefix("100.64.0.0/10")

// dialFunc opens a connection to a tailnet address.
type dialFunc func(ctx context.Context, network, addr string) (net.Conn, error)

// Node is a running in-app node and its proxy. Create it with Start and end it
// with Stop.
type Node struct {
	srv    *tsnet.Server
	lc     *local.Client
	ln     net.Listener
	proxy  *http.Server
	cancel context.CancelFunc
	done   chan struct{}

	mu        sync.Mutex
	lastError string
}

// Start brings up the node with cfg and its proxy on an ephemeral loopback
// port. onChange fires when the state, the peers or the last error change. The
// auth key is used only when cfg.StateDir holds no saved node, so a restart
// never re-registers with an expired setup code.
func Start(cfg node.Config, logf logger.Logf, onChange func()) (*Node, error) {
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(cfg.StateDir, 0o700); err != nil {
		return nil, fmt.Errorf("create state dir: %w", err)
	}
	saved, err := hasSavedNode(cfg.StateDir)
	if err != nil {
		return nil, err
	}
	authKey := ""
	if !saved {
		if strings.TrimSpace(cfg.AuthKey) == "" {
			return nil, node.ErrNotProvisioned
		}
		authKey = cfg.AuthKey
	}

	srv := &tsnet.Server{
		Dir:        cfg.StateDir,
		Hostname:   cfg.Hostname,
		ControlURL: cfg.ControlURL,
		AuthKey:    authKey,
		Logf:       logf,
		UserLogf:   logf,
	}
	if err := srv.Start(); err != nil {
		return nil, fmt.Errorf("start node: %w", err)
	}
	lc, err := srv.LocalClient()
	if err != nil {
		srv.Close()
		return nil, fmt.Errorf("local client: %w", err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		srv.Close()
		return nil, fmt.Errorf("listen proxy: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	n := &Node{srv: srv, lc: lc, ln: ln, cancel: cancel, done: make(chan struct{})}
	n.proxy = &http.Server{Handler: proxyHandler(meshDial(srv.Dial, lc), logf), ReadHeaderTimeout: 10 * time.Second}
	go func() {
		if err := n.proxy.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logf("proxy stopped: %v", err)
		}
	}()
	watcher, err := lc.WatchIPNBus(ctx, ipn.NotifyInitialState)
	if err != nil {
		cancel()
		n.proxy.Close()
		srv.Close()
		return nil, fmt.Errorf("watch node: %w", err)
	}
	go n.watch(watcher, logf, onChange)
	return n, nil
}

// hasSavedNode reports whether dir holds a node identity from an earlier login.
func hasSavedNode(dir string) (bool, error) {
	_, err := os.Stat(filepath.Join(dir, node.StateFile))
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("read saved node: %w", err)
	}
	return true, nil
}

// watch records control errors and calls onChange until the node stops.
func (n *Node) watch(w *local.IPNBusWatcher, logf logger.Logf, onChange func()) {
	defer close(n.done)
	defer w.Close()
	for {
		msg, err := w.Next()
		if err != nil {
			if !errors.Is(err, context.Canceled) {
				logf("node watch ended: %v", err)
			}
			return
		}
		if msg.ErrMessage != nil {
			n.mu.Lock()
			n.lastError = *msg.ErrMessage
			n.mu.Unlock()
		}
		if msg.State != nil || msg.NetMap != nil || msg.ErrMessage != nil {
			onChange()
		}
	}
}

// Port is the loopback port of the CONNECT proxy the app sends its requests to.
func (n *Node) Port() int {
	return n.ln.Addr().(*net.TCPAddr).Port
}

// Status reports the node's current state, self address and peers.
func (n *Node) Status(ctx context.Context) (node.Status, error) {
	st, err := n.lc.Status(ctx)
	if err != nil {
		return node.Status{}, fmt.Errorf("status: %w", err)
	}
	n.mu.Lock()
	defer n.mu.Unlock()
	return node.StatusFrom(st, n.lastError), nil
}

// Stop shuts down the proxy and the node.
func (n *Node) Stop() {
	n.cancel()
	n.proxy.Close()
	n.srv.Close()
	<-n.done
}

// meshDial dials addr over the tailnet. Host names resolve through MagicDNS,
// so Headscale's extra records (hath.dadi, yaad.dadi, …) work the same as at
// 100.100.100.100 on a device with a system tunnel; tsnet's own dialer only
// knows node names.
func meshDial(dial dialFunc, lc *local.Client) dialFunc {
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		host, port, err := net.SplitHostPort(addr)
		if err != nil {
			return nil, err
		}
		if _, err := netip.ParseAddr(host); err == nil {
			return dial(ctx, network, addr)
		}
		raw, _, err := lc.QueryDNS(ctx, host, "A")
		if err != nil {
			return nil, fmt.Errorf("magicdns %s: %w", host, err)
		}
		ip, err := firstA(raw)
		if err != nil {
			return nil, fmt.Errorf("magicdns %s: %w", host, err)
		}
		return dial(ctx, network, net.JoinHostPort(ip.String(), port))
	}
}

// firstA returns the first A record in a raw DNS response.
func firstA(raw []byte) (netip.Addr, error) {
	var p dnsmessage.Parser
	if _, err := p.Start(raw); err != nil {
		return netip.Addr{}, err
	}
	if err := p.SkipAllQuestions(); err != nil {
		return netip.Addr{}, err
	}
	for {
		h, err := p.AnswerHeader()
		if errors.Is(err, dnsmessage.ErrSectionDone) {
			return netip.Addr{}, errors.New("no A record")
		}
		if err != nil {
			return netip.Addr{}, err
		}
		if h.Type == dnsmessage.TypeA {
			r, err := p.AResource()
			if err != nil {
				return netip.Addr{}, err
			}
			return netip.AddrFrom4(r.A), nil
		}
		if err := p.SkipAnswer(); err != nil {
			return netip.Addr{}, err
		}
	}
}

// allowedTarget reports whether host is a dadi name or a mesh address. The
// proxy listens on loopback, so this keeps other software on the device from
// using it to reach anything else.
func allowedTarget(host string) bool {
	if ip, err := netip.ParseAddr(host); err == nil {
		return meshPrefix.Contains(ip)
	}
	return strings.HasSuffix(strings.ToLower(host), ".dadi")
}

// proxyHandler serves CONNECT requests to dadi destinations by splicing the
// client connection to a tailnet connection from dial.
func proxyHandler(dial dialFunc, logf logger.Logf) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect {
			http.Error(w, "the dadi proxy only accepts CONNECT", http.StatusMethodNotAllowed)
			return
		}
		host, _, err := net.SplitHostPort(r.Host)
		if err != nil {
			http.Error(w, "CONNECT target must be host:port", http.StatusBadRequest)
			return
		}
		if !allowedTarget(host) {
			http.Error(w, "the dadi proxy only reaches *.dadi and mesh addresses", http.StatusForbidden)
			return
		}
		upstream, err := dial(r.Context(), "tcp", r.Host)
		if err != nil {
			logf("proxy dial %s: %v", r.Host, err)
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		hj, ok := w.(http.Hijacker)
		if !ok {
			upstream.Close()
			http.Error(w, "connection cannot be hijacked", http.StatusInternalServerError)
			return
		}
		client, buf, err := hj.Hijack()
		if err != nil {
			upstream.Close()
			logf("proxy hijack %s: %v", r.Host, err)
			return
		}
		if _, err := client.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); err != nil {
			client.Close()
			upstream.Close()
			logf("proxy %s: %v", r.Host, err)
			return
		}
		splice(client, io.MultiReader(buf, client), upstream)
	})
}

// splice copies both directions until either side closes, then closes both.
// A copy error is how a tunneled stream ends, so it is not reported.
func splice(client net.Conn, fromClient io.Reader, upstream net.Conn) {
	done := make(chan struct{}, 2)
	go func() {
		io.Copy(upstream, fromClient)
		done <- struct{}{}
	}()
	go func() {
		io.Copy(client, upstream)
		done <- struct{}{}
	}()
	<-done
	client.Close()
	upstream.Close()
	<-done
}
