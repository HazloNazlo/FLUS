package socks5

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"sync"
	"time"
)

type Dialer interface {
	DialTCP(address string) (net.Conn, error)
}
type SOCKS5Server struct {
	listenAddr string
	dialer     Dialer
}

func NewSOCKS5Server(addr string, dialer Dialer) *SOCKS5Server {
	return &SOCKS5Server{listenAddr: addr, dialer: dialer}
}
func (s *SOCKS5Server) Start() error {
	listener, err := net.Listen("tcp", s.listenAddr)
	if err != nil {
		return err
	}
	defer listener.Close()
	fmt.Println("FLUS_LISTENING")
	slots := make(chan struct{}, 256)
	for {
		conn, err := listener.Accept()
		if err != nil {
			return err
		}
		select {
		case slots <- struct{}{}:
			go func() { defer func() { <-slots }(); s.handleConnection(conn) }()
		default:
			conn.Close()
		}
	}
}
func request(client net.Conn) (string, error) {
	header := make([]byte, 2)
	if _, err := io.ReadFull(client, header); err != nil {
		return "", err
	}
	if header[0] != 5 || header[1] == 0 {
		return "", fmt.Errorf("invalid greeting")
	}
	methods := make([]byte, int(header[1]))
	if _, err := io.ReadFull(client, methods); err != nil {
		return "", err
	}
	noAuth := false
	for _, method := range methods {
		if method == 0 {
			noAuth = true
		}
	}
	if !noAuth {
		client.Write([]byte{5, 255})
		return "", fmt.Errorf("unsupported auth")
	}
	if _, err := client.Write([]byte{5, 0}); err != nil {
		return "", err
	}
	req := make([]byte, 4)
	if _, err := io.ReadFull(client, req); err != nil {
		return "", err
	}
	if req[0] != 5 || req[1] != 1 || req[2] != 0 {
		client.Write([]byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
		return "", fmt.Errorf("only CONNECT supported")
	}
	var host string
	switch req[3] {
	case 1:
		ip := make([]byte, 4)
		if _, err := io.ReadFull(client, ip); err != nil {
			return "", err
		}
		host = net.IP(ip).String()
	case 3:
		length := make([]byte, 1)
		if _, err := io.ReadFull(client, length); err != nil {
			return "", err
		}
		if length[0] == 0 {
			return "", fmt.Errorf("empty domain")
		}
		name := make([]byte, int(length[0]))
		if _, err := io.ReadFull(client, name); err != nil {
			return "", err
		}
		host = string(name)
	default:
		client.Write([]byte{5, 8, 0, 1, 0, 0, 0, 0, 0, 0})
		return "", fmt.Errorf("IPv4/domain only")
	}
	port := make([]byte, 2)
	if _, err := io.ReadFull(client, port); err != nil {
		return "", err
	}
	return net.JoinHostPort(host, fmt.Sprint(binary.BigEndian.Uint16(port))), nil
}
func (s *SOCKS5Server) handleConnection(client net.Conn) {
	defer client.Close()
	client.SetDeadline(time.Now().Add(15 * time.Second))
	address, err := request(client)
	if err != nil {
		return
	}
	target, err := s.dialer.DialTCP(address)
	if err != nil {
		client.Write([]byte{5, 4, 0, 1, 0, 0, 0, 0, 0, 0})
		return
	}
	defer target.Close()
	if _, err = client.Write([]byte{5, 0, 0, 1, 0, 0, 0, 0, 0, 0}); err != nil {
		return
	}
	client.SetDeadline(time.Time{})
	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); defer target.Close(); io.Copy(target, client) }()
	go func() { defer wg.Done(); defer client.Close(); io.Copy(client, target) }()
	wg.Wait()
}
