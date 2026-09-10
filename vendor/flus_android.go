package main

import (
	"os"
	"time"
)

// A child process must not outlive its Android service process, including
// SIGKILL / force-stop paths where Service.onDestroy is never called.
func init() {
	parent := os.Getppid()
	if parent <= 1 {
		os.Exit(1)
	}
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if os.Getppid() != parent {
				os.Exit(0)
			}
		}
	}()
}
