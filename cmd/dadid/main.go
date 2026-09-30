// Command dadid is dadi's network service on Windows and Linux. It runs as
// root or LocalSystem, creates the dadi tunnel, and serves the local API the
// dadi app uses to provision the device and turn dadi on and off.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/dadi-os/khisso/internal/node"
	"github.com/dadi-os/khisso/internal/service"
	"tailscale.com/safesocket"
)

// tunName is the tunnel interface dadid creates.
const tunName = "dadi"

func main() {
	stateDir := flag.String("state-dir", "", "directory for settings and node state (required)")
	socket := flag.String("socket", "", "local API socket path, or named pipe on Windows (required)")
	flag.Parse()
	if strings.TrimSpace(*stateDir) == "" || strings.TrimSpace(*socket) == "" {
		logf("error", "--state-dir and --socket are required")
		os.Exit(2)
	}
	if err := runService(func(ctx context.Context) error { return run(ctx, *stateDir, *socket) }); err != nil {
		logf("error", "%v", err)
		os.Exit(1)
	}
}

// run serves the local API until ctx ends, then stops the node.
func run(ctx context.Context, stateDir, socket string) error {
	nodeLog := func(format string, args ...any) { logf("info", format, args...) }
	start := func(cfg node.Config) (service.Runner, error) {
		return node.Start(cfg, node.SystemNetwork(tunName), nodeLog, func() {})
	}
	svc, err := service.New(stateDir, start, nodeLog)
	if err != nil {
		return err
	}
	defer svc.Close()

	ln, err := safesocket.Listen(socket)
	if err != nil {
		return fmt.Errorf("listen %s: %w", socket, err)
	}
	srv := &http.Server{Handler: svc.Handler(), ReadHeaderTimeout: 10 * time.Second}
	served := make(chan error, 1)
	go func() { served <- srv.Serve(ln) }()
	logf("info", "dadid serving on %s", socket)

	select {
	case err := <-served:
		return fmt.Errorf("serve: %w", err)
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdown); err != nil && !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("shutdown: %w", err)
		}
		logf("info", "dadid stopped")
		return nil
	}
}

// logf writes one structured log line to stdout for the service manager.
func logf(level, format string, args ...any) {
	line, err := json.Marshal(map[string]string{
		"time":    time.Now().UTC().Format(time.RFC3339Nano),
		"level":   level,
		"service": "dadid",
		"msg":     fmt.Sprintf(format, args...),
	})
	if err != nil {
		panic(err)
	}
	fmt.Println(string(line))
}
