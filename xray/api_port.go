package xray

import (
	"fmt"
	"math"
	"net"
)

const (
	openUIAPIPortStart = 42001
	openUIAPIPortEnd   = 42999
)

func ensureAPIPortAvailable(cfg *Config) (int, bool, error) {
	if cfg == nil {
		return 0, false, fmt.Errorf("xray config is nil")
	}

	apiIdx := -1
	for i := range cfg.InboundConfigs {
		if cfg.InboundConfigs[i].Tag == "api" {
			apiIdx = i
			break
		}
	}
	if apiIdx < 0 {
		return 0, false, fmt.Errorf("xray api inbound not found")
	}

	current := cfg.InboundConfigs[apiIdx].Port
	if isValidPort(current) && isLocalTCPPortAvailable(current) {
		return current, false, nil
	}

	replacement, err := findAvailableLocalTCPPort()
	if err != nil {
		return 0, false, err
	}
	cfg.InboundConfigs[apiIdx].Port = replacement
	return replacement, true, nil
}

func isValidPort(port int) bool {
	return port > 0 && port <= math.MaxUint16
}

func findAvailableLocalTCPPort() (int, error) {
	for port := openUIAPIPortStart; port <= openUIAPIPortEnd; port++ {
		if isLocalTCPPortAvailable(port) {
			return port, nil
		}
	}
	return 0, fmt.Errorf("no available local TCP port found in %d-%d for xray api", openUIAPIPortStart, openUIAPIPortEnd)
}

func isLocalTCPPortAvailable(port int) bool {
	listener, err := net.ListenTCP("tcp", &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: port})
	if err != nil {
		return false
	}
	_ = listener.Close()
	return true
}
