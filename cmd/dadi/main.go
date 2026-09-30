//go:build darwin

// Command dadi is the C interface to the node package, built with
// -buildmode=c-archive into Dadi.xcframework for the dadi packet-tunnel
// extensions. One extension process runs at most one node.
package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef void (*dadi_text_fn)(void *ctx, const char *text);
typedef void (*dadi_change_fn)(void *ctx);

static void dadi_call_text(dadi_text_fn fn, void *ctx, const char *text) { fn(ctx, text); }
static void dadi_call_change(dadi_change_fn fn, void *ctx) { fn(ctx); }
*/
import "C"

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"runtime"
	"runtime/debug"
	"sync"
	"time"
	"unsafe"

	"github.com/dadi-os/khisso/internal/node"
	"github.com/dadi-os/khisso/internal/utun"
	"github.com/tailscale/wireguard-go/tun"
)

// tunnelMTU matches the MTU the extension sets in its tunnel network settings.
const tunnelMTU = 1280

// iosMemoryLimit keeps the Go heap well inside iOS's 50 MB packet-tunnel cap.
const iosMemoryLimit = 36 << 20

var (
	mu        sync.Mutex
	running   *node.Node
	lastError string
)

// callbacks carries the extension's C callbacks and their context pointer.
type callbacks struct {
	onRoutes C.dadi_text_fn
	onChange C.dadi_change_fn
	onLog    C.dadi_text_fn
	ctx      unsafe.Pointer
}

func (c callbacks) text(fn C.dadi_text_fn, s string) {
	cs := C.CString(s)
	defer C.free(unsafe.Pointer(cs))
	C.dadi_call_text(fn, c.ctx, cs)
}

// log formats one structured log line and hands it to the extension.
func (c callbacks) log(level, msg string) {
	line, err := json.Marshal(map[string]string{
		"time":    time.Now().UTC().Format(time.RFC3339Nano),
		"level":   level,
		"service": "dadi",
		"msg":     msg,
	})
	if err != nil {
		panic(err)
	}
	c.text(c.onLog, string(line))
}

// dadi_start runs a node on this extension's utun with the JSON config
// (node.Config). on_routes receives node.RouteSettings JSON, on_change
// fires on state changes and on_log receives structured log lines. Returns 0,
// or -1 with the reason in dadi_last_error.
//
//export dadi_start
func dadi_start(configJSON *C.char, onRoutes C.dadi_text_fn, onChange C.dadi_change_fn, onLog C.dadi_text_fn, ctx unsafe.Pointer) C.int32_t {
	mu.Lock()
	defer mu.Unlock()
	if err := start(C.GoString(configJSON), callbacks{onRoutes: onRoutes, onChange: onChange, onLog: onLog, ctx: ctx}); err != nil {
		lastError = err.Error()
		return -1
	}
	lastError = ""
	return 0
}

func start(configJSON string, cb callbacks) error {
	if running != nil {
		return errors.New("a node is already running")
	}
	var cfg node.Config
	if err := json.Unmarshal([]byte(configJSON), &cfg); err != nil {
		return fmt.Errorf("config: %w", err)
	}
	if runtime.GOOS == "ios" {
		debug.SetMemoryLimit(iosMemoryLimit)
	}
	fd, err := utun.FindDescriptor()
	if err != nil {
		return err
	}
	dev, err := tun.CreateTUNFromFile(os.NewFile(uintptr(fd), "utun"), tunnelMTU)
	if err != nil {
		return fmt.Errorf("tunnel device: %w", err)
	}
	logf := func(format string, args ...any) { cb.log("info", fmt.Sprintf(format, args...)) }
	onRoutes := func(s node.RouteSettings) {
		b, err := json.Marshal(s)
		if err != nil {
			panic(err)
		}
		cb.text(cb.onRoutes, string(b))
	}
	onChange := func() { C.dadi_call_change(cb.onChange, cb.ctx) }
	n, err := node.Start(cfg, node.ExtensionNetwork(dev, onRoutes), logf, onChange)
	if err != nil {
		dev.Close()
		return err
	}
	running = n
	return nil
}

// dadi_stop stops the running node, if any.
//
//export dadi_stop
func dadi_stop() {
	mu.Lock()
	defer mu.Unlock()
	if running == nil {
		return
	}
	running.Stop()
	running = nil
}

// dadi_status returns node.Status JSON, or NULL with the reason in
// dadi_last_error. Free the result with dadi_free.
//
//export dadi_status
func dadi_status() *C.char {
	mu.Lock()
	defer mu.Unlock()
	if running == nil {
		lastError = "no node is running"
		return nil
	}
	b, err := running.StatusJSON()
	if err != nil {
		lastError = err.Error()
		return nil
	}
	return C.CString(string(b))
}

// dadi_last_error returns the most recent failure's message, empty when the
// last call succeeded. Free the result with dadi_free.
//
//export dadi_last_error
func dadi_last_error() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return C.CString(lastError)
}

// dadi_free releases a string returned by this library.
//
//export dadi_free
func dadi_free(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func main() {}
