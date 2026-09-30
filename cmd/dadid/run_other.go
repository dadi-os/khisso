//go:build !windows

package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"
)

// runService runs until SIGINT or SIGTERM, which is how systemd stops dadid.
func runService(run func(context.Context) error) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return run(ctx)
}
