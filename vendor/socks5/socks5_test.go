package socks5

import (
	"io"
	"net"
	"testing"
	"time"
)

func TestFragmentedDomainRequest(t *testing.T) {
	server, client := net.Pipe()
	defer client.Close()
	defer server.Close()
	server.SetDeadline(time.Now().Add(3 * time.Second))
	client.SetDeadline(time.Now().Add(3 * time.Second))
	done := make(chan string, 1)
	go func() {
		addr, err := request(server)
		if err != nil {
			done <- "error"
			return
		}
		done <- addr
	}()
	// Split the greeting and request into individual TCP writes.
	for _, b := range []byte{5, 1, 0} {
		if _, err := client.Write([]byte{b}); err != nil {
			t.Fatal(err)
		}
	}
	reply := make([]byte, 2)
	if _, err := io.ReadFull(client, reply); err != nil {
		t.Fatal(err)
	}
	if reply[0] != 5 || reply[1] != 0 {
		t.Fatal("unexpected greeting")
	}
	req := append([]byte{5, 1, 0, 3, 11}, []byte("example.com")...)
	req = append(req, 1, 187)
	for _, b := range req {
		if _, err := client.Write([]byte{b}); err != nil {
			t.Fatal(err)
		}
	}
	if got := <-done; got != "example.com:443" {
		t.Fatalf("unexpected destination %q", got)
	}
}

func TestRejectsUnsupportedAuthentication(t *testing.T) {
	server, client := net.Pipe()
	defer server.Close()
	defer client.Close()
	server.SetDeadline(time.Now().Add(time.Second))
	client.SetDeadline(time.Now().Add(time.Second))
	done := make(chan error, 1)
	go func() { _, err := request(server); done <- err }()
	client.Write([]byte{5, 1, 2})
	reply := make([]byte, 2)
	io.ReadFull(client, reply)
	if reply[1] != 255 {
		t.Fatal("authentication should be rejected")
	}
	if <-done == nil {
		t.Fatal("expected error")
	}
}

func TestTruncatedRequestDoesNotPanic(t *testing.T) {
	server, client := net.Pipe()
	defer server.Close()
	done := make(chan error, 1)
	go func() { _, err := request(server); done <- err }()
	client.Write([]byte{5, 1, 0})
	reply := make([]byte, 2)
	io.ReadFull(client, reply)
	client.Write([]byte{5, 1, 0, 3, 20, 'x'})
	client.Close()
	if <-done == nil {
		t.Fatal("expected EOF")
	}
}
