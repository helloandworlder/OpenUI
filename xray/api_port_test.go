package xray

import (
	"net"
	"testing"

	"github.com/mhsanaei/3x-ui/v3/util/json_util"
)

func TestEnsureAPIPortAvailableKeepsFreePort(t *testing.T) {
	port := freeTCPPort(t)
	cfg := apiPortTestConfig(port)

	got, changed, err := ensureAPIPortAvailable(cfg)
	if err != nil {
		t.Fatalf("ensureAPIPortAvailable: %v", err)
	}
	if changed {
		t.Fatal("changed free api port")
	}
	if got != port {
		t.Fatalf("api port = %d, want %d", got, port)
	}
	if cfg.InboundConfigs[0].Port != port {
		t.Fatalf("config api port = %d, want %d", cfg.InboundConfigs[0].Port, port)
	}
}

func TestEnsureAPIPortAvailableReplacesOccupiedPort(t *testing.T) {
	listener := listenLocalTCP(t, 0)
	defer listener.Close()
	occupied := listener.Addr().(*net.TCPAddr).Port
	cfg := apiPortTestConfig(occupied)

	got, changed, err := ensureAPIPortAvailable(cfg)
	if err != nil {
		t.Fatalf("ensureAPIPortAvailable: %v", err)
	}
	if !changed {
		t.Fatal("did not change occupied api port")
	}
	if got == occupied {
		t.Fatalf("api port stayed on occupied port %d", occupied)
	}
	if cfg.InboundConfigs[0].Port != got {
		t.Fatalf("config api port = %d, want %d", cfg.InboundConfigs[0].Port, got)
	}
	assertCanListenLocalTCP(t, got)
}

func TestEnsureAPIPortAvailableReplacesInvalidPort(t *testing.T) {
	cfg := apiPortTestConfig(0)

	got, changed, err := ensureAPIPortAvailable(cfg)
	if err != nil {
		t.Fatalf("ensureAPIPortAvailable: %v", err)
	}
	if !changed {
		t.Fatal("did not change invalid api port")
	}
	if got <= 0 {
		t.Fatalf("api port = %d, want valid port", got)
	}
	if cfg.InboundConfigs[0].Port != got {
		t.Fatalf("config api port = %d, want %d", cfg.InboundConfigs[0].Port, got)
	}
	assertCanListenLocalTCP(t, got)
}

func apiPortTestConfig(port int) *Config {
	return &Config{
		InboundConfigs: []InboundConfig{
			{
				Tag:      "api",
				Listen:   json_util.RawMessage(`"127.0.0.1"`),
				Port:     port,
				Protocol: "dokodemo-door",
			},
		},
	}
}

func freeTCPPort(t *testing.T) int {
	t.Helper()
	listener := listenLocalTCP(t, 0)
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port
}

func listenLocalTCP(t *testing.T, port int) net.Listener {
	t.Helper()
	listener, err := net.ListenTCP("tcp", &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: port})
	if err != nil {
		t.Fatalf("listen tcp port %d: %v", port, err)
	}
	return listener
}

func assertCanListenLocalTCP(t *testing.T, port int) {
	t.Helper()
	listener := listenLocalTCP(t, port)
	_ = listener.Close()
}
