package inapp

import (
	"bufio"
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"strings"
	"testing"

	"github.com/dadi-os/khisso/internal/node"
	"golang.org/x/net/dns/dnsmessage"
)

func TestFirstASkipsOtherRecords(t *testing.T) {
	b := dnsmessage.NewBuilder(nil, dnsmessage.Header{Response: true})
	b.StartQuestions()
	name := dnsmessage.MustNewName("hath.dadi.")
	b.Question(dnsmessage.Question{Name: name, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET})
	b.StartAnswers()
	b.CNAMEResource(dnsmessage.ResourceHeader{Name: name, Class: dnsmessage.ClassINET}, dnsmessage.CNAMEResource{CNAME: dnsmessage.MustNewName("os.dadi.")})
	b.AResource(dnsmessage.ResourceHeader{Name: name, Class: dnsmessage.ClassINET}, dnsmessage.AResource{A: [4]byte{100, 64, 0, 1}})
	raw, err := b.Finish()
	if err != nil {
		t.Fatal(err)
	}
	ip, err := firstA(raw)
	if err != nil || ip != netip.MustParseAddr("100.64.0.1") {
		t.Fatalf("firstA = %v, %v", ip, err)
	}
}

func TestFirstAWithoutARecordFails(t *testing.T) {
	b := dnsmessage.NewBuilder(nil, dnsmessage.Header{Response: true})
	b.StartQuestions()
	b.Question(dnsmessage.Question{Name: dnsmessage.MustNewName("nope.dadi."), Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET})
	raw, err := b.Finish()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := firstA(raw); err == nil {
		t.Fatal("firstA succeeded with no answers")
	}
}

func TestAllowedTargetIsDadiOnly(t *testing.T) {
	for host, want := range map[string]bool{
		"hath.dadi": true, "OS.DADI": true, "100.64.0.1": true, "100.127.255.254": true,
		"example.com": false, "dadi": false, "10.0.0.1": false, "127.0.0.1": false,
	} {
		if got := allowedTarget(host); got != want {
			t.Errorf("allowedTarget(%q) = %v, want %v", host, got, want)
		}
	}
}

// echoDial returns a dial func that connects every request to a local echo
// server and records the requested address.
func echoDial(t *testing.T, dialed *string) dialFunc {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() { io.Copy(c, c); c.Close() }()
		}
	}()
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		*dialed = addr
		return net.Dial("tcp", ln.Addr().String())
	}
}

func TestProxyTunnelsConnectToDadi(t *testing.T) {
	var dialed string
	srv := httptest.NewServer(proxyHandler(echoDial(t, &dialed), t.Logf))
	defer srv.Close()

	c, err := net.Dial("tcp", strings.TrimPrefix(srv.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if _, err := io.WriteString(c, "CONNECT hath.dadi:80 HTTP/1.1\r\nHost: hath.dadi:80\r\n\r\n"); err != nil {
		t.Fatal(err)
	}
	br := bufio.NewReader(c)
	resp, err := http.ReadResponse(br, nil)
	if err != nil || resp.StatusCode != http.StatusOK {
		t.Fatalf("CONNECT = %v, %v", resp, err)
	}
	if dialed != "hath.dadi:80" {
		t.Errorf("dialed %q, want hath.dadi:80", dialed)
	}
	if _, err := io.WriteString(c, "ping"); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, 4)
	if _, err := io.ReadFull(br, got); err != nil || string(got) != "ping" {
		t.Fatalf("echo = %q, %v", got, err)
	}
}

func TestProxyRefusesOtherRequests(t *testing.T) {
	var dialed string
	srv := httptest.NewServer(proxyHandler(echoDial(t, &dialed), t.Logf))
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("GET = %d, want 405", resp.StatusCode)
	}

	c, err := net.Dial("tcp", strings.TrimPrefix(srv.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	io.WriteString(c, "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n")
	resp, err = http.ReadResponse(bufio.NewReader(c), nil)
	if err != nil || resp.StatusCode != http.StatusForbidden {
		t.Fatalf("CONNECT example.com = %v, %v, want 403", resp, err)
	}
	if dialed != "" {
		t.Errorf("dialed %q for a refused target", dialed)
	}
}

func TestProxyReportsDialFailure(t *testing.T) {
	srv := httptest.NewServer(proxyHandler(func(context.Context, string, string) (net.Conn, error) {
		return nil, errors.New("magicdns hath.dadi: no A record")
	}, t.Logf))
	defer srv.Close()
	c, err := net.Dial("tcp", strings.TrimPrefix(srv.URL, "http://"))
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	io.WriteString(c, "CONNECT hath.dadi:80 HTTP/1.1\r\nHost: hath.dadi:80\r\n\r\n")
	resp, err := http.ReadResponse(bufio.NewReader(c), nil)
	if err != nil || resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("CONNECT = %v, %v, want 502", resp, err)
	}
}

func TestStartWithoutNodeOrKeyIsNotProvisioned(t *testing.T) {
	cfg := node.Config{ControlURL: "http://127.0.0.1:1", Hostname: "test", StateDir: t.TempDir()}
	if _, err := Start(cfg, t.Logf, func() {}); !errors.Is(err, node.ErrNotProvisioned) {
		t.Fatalf("Start() err = %v, want ErrNotProvisioned", err)
	}
}

func TestStartRunsAgainstUnreachableControl(t *testing.T) {
	cfg := node.Config{ControlURL: "http://127.0.0.1:1", Hostname: "test", AuthKey: "tskey-test", StateDir: t.TempDir()}
	changed := make(chan struct{}, 16)
	n, err := Start(cfg, t.Logf, func() {
		select {
		case changed <- struct{}{}:
		default:
		}
	})
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer n.Stop()
	<-changed
	if n.Port() == 0 {
		t.Error("proxy port is 0")
	}
	st, err := n.Status(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if st.BackendState == "Running" || st.Peers == nil {
		t.Errorf("status = %+v, want not running with an empty peer list", st)
	}
}
