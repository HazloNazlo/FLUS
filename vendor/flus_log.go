package main

import (
	"io"
	"os"
	"strings"
)

// FLUS only emits known event codes, never upstream exception text, tokens,
// document URLs, packet contents or destination addresses. Kotlin translates.
type flusLogWriter struct{}

func (flusLogWriter) Write(data []byte) (int, error) {
	text := string(data)
	code := ""
	switch {
	case strings.Contains(text, "address already in use"):
		code = "address already in use"
	case strings.Contains(text, "fetchDocInfo failed"):
		code = "fetchDocInfo failed"
	case strings.Contains(text, "Read error"), strings.Contains(text, "WebSocket dial failed"), strings.Contains(text, "Write error"):
		code = "websocket error"
	case strings.Contains(text, "Failed to start transport"):
		code = "Failed to start transport"
	case strings.Contains(text, "connectToDoc attempt"):
		code = "connectToDoc attempt"
	case strings.Contains(text, "Keep-alive failed"):
		code = "Keep-alive failed"
	}
	if code != "" {
		_, _ = io.WriteString(os.Stderr, code+"\n")
	}
	return len(data), nil
}
