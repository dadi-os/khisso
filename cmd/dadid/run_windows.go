package main

import (
	"context"
	"os"
	"os/signal"

	"golang.org/x/sys/windows/svc"
)

// serviceName is the Windows service name dadid registers under.
const serviceName = "dadid"

// runService runs under the Service Control Manager when started as a service,
// and until Ctrl+C when started from a console.
func runService(run func(context.Context) error) error {
	isService, err := svc.IsWindowsService()
	if err != nil {
		return err
	}
	if !isService {
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
		defer stop()
		return run(ctx)
	}
	return svc.Run(serviceName, &handler{run: run})
}

// handler adapts run to the Service Control Manager's start and stop requests.
type handler struct {
	run func(context.Context) error
}

func (h *handler) Execute(_ []string, requests <-chan svc.ChangeRequest, status chan<- svc.Status) (bool, uint32) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- h.run(ctx) }()
	status <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	for {
		select {
		case err := <-done:
			if err != nil {
				logf("error", "%v", err)
				return false, 1
			}
			return false, 0
		case req := <-requests:
			switch req.Cmd {
			case svc.Interrogate:
				status <- req.CurrentStatus
			case svc.Stop, svc.Shutdown:
				status <- svc.Status{State: svc.StopPending}
				cancel()
			}
		}
	}
}
