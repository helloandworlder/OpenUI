package service

import (
	"encoding/json"
	"testing"

	"github.com/mhsanaei/3x-ui/v3/database"
	"github.com/mhsanaei/3x-ui/v3/database/model"
	xray "github.com/mhsanaei/3x-ui/v3/xray"
)

func TestNormalizeAccountClientsCoercesEmptyStringTgID(t *testing.T) {
	settings := map[string]any{
		"accounts": []any{
			map[string]any{
				"user":  "O7UG0GCmjF",
				"pass":  "O2mlK1rExg",
				"email": "O7UG0GCmjF",
				"tgId":  "",
			},
		},
	}

	normalizeAccountClients(model.Mixed, settings)

	if _, ok := settings["accounts"]; ok {
		t.Fatalf("settings.accounts should be removed after panel normalization: %#v", settings["accounts"])
	}
	clients, ok := settings["clients"].([]any)
	if !ok || len(clients) != 1 {
		t.Fatalf("clients = %#v, want one client", settings["clients"])
	}
	client, ok := clients[0].(map[string]any)
	if !ok {
		t.Fatalf("clients[0] = %#v, want map", clients[0])
	}
	if got := client["tgId"]; got != int64(0) {
		t.Fatalf("clients[0].tgId = %#v, want int64(0)", got)
	}

	out, err := json.Marshal(settings)
	if err != nil {
		t.Fatal(err)
	}
	if json.Valid(out) == false {
		t.Fatalf("normalised settings are not valid JSON: %s", out)
	}
}

func TestNormalizeAccountClientsStoresClientsOnlyAndDefaultsEmail(t *testing.T) {
	settings := map[string]any{
		"accounts": []any{
			map[string]any{
				"user": "legacy-user",
				"pass": "legacy-pass",
			},
		},
	}

	normalizeAccountClients(model.HTTP, settings)

	if _, ok := settings["accounts"]; ok {
		t.Fatalf("accounts should not remain in stored settings: %#v", settings["accounts"])
	}
	clients := settings["clients"].([]any)
	client := clients[0].(map[string]any)
	if client["email"] != "legacy-user" {
		t.Fatalf("email = %#v, want user fallback", client["email"])
	}
	if client["enable"] != true {
		t.Fatalf("enable = %#v, want true default", client["enable"])
	}
}

func TestGetClientsReadsLegacyHTTPAccountsAndDefaultsEmail(t *testing.T) {
	inbound := &model.Inbound{
		Protocol: model.HTTP,
		Settings: `{
			"accounts": [
				{"user":"legacy-http","pass":"secret","enable":true}
			]
		}`,
	}

	clients, err := new(InboundService).GetClients(inbound)
	if err != nil {
		t.Fatal(err)
	}
	if len(clients) != 1 {
		t.Fatalf("len(clients) = %d, want 1", len(clients))
	}
	client := clients[0]
	if client.User != "legacy-http" || client.Pass != "secret" {
		t.Fatalf("unexpected client credentials: %#v", client)
	}
	if client.Email != "legacy-http" {
		t.Fatalf("Email = %q, want user fallback", client.Email)
	}
}

func TestGetClientsMixedNoAuthReturnsNoManagedClients(t *testing.T) {
	inbound := &model.Inbound{
		Protocol: model.Mixed,
		Settings: `{
			"auth": "noauth",
			"clients": [
				{"user":"ignored","pass":"secret","email":"ignored","enable":true}
			]
		}`,
	}

	clients, err := new(InboundService).GetClients(inbound)
	if err != nil {
		t.Fatal(err)
	}
	if len(clients) != 0 {
		t.Fatalf("mixed noauth returned managed clients: %#v", clients)
	}
}

func TestAddInboundHTTPClientCreatesTrafficRow(t *testing.T) {
	setupConflictDB(t)
	inbound := &model.Inbound{
		Remark:         "http-client-management",
		Enable:         false,
		Listen:         "127.0.0.1",
		Port:           48100,
		Protocol:       model.HTTP,
		StreamSettings: `{}`,
		Sniffing:       `{}`,
		Settings: `{
			"allowTransparent": false,
			"clients": [
				{"user":"http-user","pass":"secret","email":"http-user@example","enable":true,"totalGB":1073741824,"expiryTime":1893456000000}
			]
		}`,
	}

	created, needRestart, err := new(InboundService).AddInbound(inbound)
	if err != nil {
		t.Fatal(err)
	}
	if needRestart {
		t.Fatal("disabled inbound should not require runtime restart")
	}

	var traffic xray.ClientTraffic
	if err := database.GetDB().Where("email = ?", "http-user@example").First(&traffic).Error; err != nil {
		t.Fatal(err)
	}
	if traffic.InboundId != created.Id || traffic.Total != 1073741824 || !traffic.Enable {
		t.Fatalf("unexpected client traffic row: %#v", traffic)
	}

	var stored model.Inbound
	if err := database.GetDB().First(&stored, created.Id).Error; err != nil {
		t.Fatal(err)
	}
	var settings map[string]any
	if err := json.Unmarshal([]byte(stored.Settings), &settings); err != nil {
		t.Fatal(err)
	}
	if _, ok := settings["accounts"]; ok {
		t.Fatalf("stored HTTP settings should use clients, not accounts: %#v", settings)
	}
	if clients, ok := settings["clients"].([]any); !ok || len(clients) != 1 {
		t.Fatalf("stored clients = %#v, want one client", settings["clients"])
	}
}

func TestAddInboundMixedNoAuthCreatesNoTrafficRows(t *testing.T) {
	setupConflictDB(t)
	inbound := &model.Inbound{
		Remark:         "mixed-noauth",
		Enable:         false,
		Listen:         "127.0.0.1",
		Port:           48101,
		Protocol:       model.Mixed,
		StreamSettings: `{}`,
		Sniffing:       `{}`,
		Settings: `{
			"auth": "noauth",
			"udp": false,
			"clients": [
				{"user":"ignored","pass":"secret","email":"ignored@example","enable":true}
			]
		}`,
	}

	_, _, err := new(InboundService).AddInbound(inbound)
	if err != nil {
		t.Fatal(err)
	}
	var count int64
	if err := database.GetDB().Model(xray.ClientTraffic{}).Count(&count).Error; err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("client_traffics rows = %d, want 0 for mixed noauth", count)
	}
}
