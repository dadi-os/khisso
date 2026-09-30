// Package utun finds the utun descriptor that NetworkExtension opens for a
// packet-tunnel provider. There is no public API for it, so it scans the
// process's descriptors for the utun kernel-control socket, as WireGuard's
// Apple client does.
package utun

import (
	"errors"

	"golang.org/x/sys/unix"
)

// controlName is the kernel control that backs utun interfaces.
const controlName = "com.apple.net.utun_control"

// maxDescriptor bounds the scan; an extension holds far fewer open files.
const maxDescriptor = 1024

// ErrNotFound means no descriptor in this process is a utun control socket.
var ErrNotFound = errors.New("utun descriptor not found")

// FindDescriptor returns the descriptor of the tunnel's utun interface.
func FindDescriptor() (int, error) {
	var info unix.CtlInfo
	copy(info.Name[:], controlName)
	for fd := 0; fd <= maxDescriptor; fd++ {
		sa, err := unix.Getpeername(fd)
		if err != nil {
			continue
		}
		ctl, ok := sa.(*unix.SockaddrCtl)
		if !ok {
			continue
		}
		if info.Id == 0 {
			if err := unix.IoctlCtlInfo(fd, &info); err != nil {
				continue
			}
		}
		if ctl.ID == info.Id {
			return fd, nil
		}
	}
	return 0, ErrNotFound
}
