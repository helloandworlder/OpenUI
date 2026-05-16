package model

import (
	"encoding/json"
	"testing"
)

func TestClientUnmarshalAcceptsEmptyStringTgID(t *testing.T) {
	var client Client
	err := json.Unmarshal([]byte(`{
		"user":"O7UG0GCmjF",
		"pass":"O2mlK1rExg",
		"email":"O7UG0GCmjF",
		"tgId":"",
		"enable":true
	}`), &client)
	if err != nil {
		t.Fatal(err)
	}
	if client.TgID != 0 {
		t.Fatalf("TgID = %d, want 0", client.TgID)
	}
}

func TestClientUnmarshalAcceptsStringTgID(t *testing.T) {
	var client Client
	err := json.Unmarshal([]byte(`{"email":"u","tgId":"12345","enable":true}`), &client)
	if err != nil {
		t.Fatal(err)
	}
	if client.TgID != 12345 {
		t.Fatalf("TgID = %d, want 12345", client.TgID)
	}
}

func TestMixedRuntimeSettingsProjectsClientsToAccountsWithInheritedLimits(t *testing.T) {
	inbound := Inbound{
		Protocol: Mixed,
		Settings: `{
			"auth": "password",
			"uplinkLimitBps": 1024,
			"downlinkLimitBps": 2048,
			"maxConnections": 3,
			"clients": [
				{"user":"alice","pass":"pa","email":"alice@example","enable":true,"uplinkLimitBps":0,"downlinkLimitBps":4096,"maxConnections":0,"totalGB":1073741824},
				{"user":"bob","pass":"pb","email":"bob@example","enable":false,"uplinkLimitBps":9999}
			]
		}`,
	}

	var got map[string]any
	if err := json.Unmarshal([]byte(inbound.XrayRuntimeSettings()), &got); err != nil {
		t.Fatal(err)
	}
	if _, ok := got["clients"]; ok {
		t.Fatalf("runtime settings leaked panel clients: %#v", got["clients"])
	}
	for _, key := range []string{"uplinkLimitBps", "downlinkLimitBps", "maxConnections"} {
		if _, ok := got[key]; ok {
			t.Fatalf("runtime settings leaked panel default %s: %#v", key, got[key])
		}
	}
	accounts, ok := got["accounts"].([]any)
	if !ok || len(accounts) != 1 {
		t.Fatalf("accounts = %#v, want one enabled runtime account", got["accounts"])
	}
	account := accounts[0].(map[string]any)
	if account["user"] != "alice" || account["pass"] != "pa" || account["email"] != "alice@example" {
		t.Fatalf("unexpected runtime account identity: %#v", account)
	}
	if account["uplinkLimitBps"] != float64(1024) {
		t.Fatalf("uplinkLimitBps = %#v, want inherited 1024", account["uplinkLimitBps"])
	}
	if account["downlinkLimitBps"] != float64(4096) {
		t.Fatalf("downlinkLimitBps = %#v, want client override 4096", account["downlinkLimitBps"])
	}
	if account["maxConnections"] != float64(3) {
		t.Fatalf("maxConnections = %#v, want inherited 3", account["maxConnections"])
	}
	if _, ok := account["totalGB"]; ok {
		t.Fatalf("runtime account leaked panel-only totalGB: %#v", account)
	}
}

func TestHTTPRuntimeSettingsDefaultsEmailFromLegacyAccountUser(t *testing.T) {
	inbound := Inbound{
		Protocol: HTTP,
		Settings: `{
			"allowTransparent": true,
			"accounts": [
				{"user":"legacy-user","pass":"legacy-pass","enable":true}
			]
		}`,
	}

	var got map[string]any
	if err := json.Unmarshal([]byte(inbound.XrayRuntimeSettings()), &got); err != nil {
		t.Fatal(err)
	}
	accounts := got["accounts"].([]any)
	account := accounts[0].(map[string]any)
	if account["email"] != "legacy-user" {
		t.Fatalf("email = %#v, want user fallback", account["email"])
	}
	if got["allowTransparent"] != true {
		t.Fatalf("allowTransparent = %#v, want true", got["allowTransparent"])
	}
}

func TestMixedNoAuthRuntimeSettingsOmitsAccounts(t *testing.T) {
	inbound := Inbound{
		Protocol: Mixed,
		Settings: `{
			"auth": "noauth",
			"udp": true,
			"clients": [
				{"user":"should-not-run","pass":"secret","email":"blocked","enable":true}
			]
		}`,
	}

	var got map[string]any
	if err := json.Unmarshal([]byte(inbound.XrayRuntimeSettings()), &got); err != nil {
		t.Fatal(err)
	}
	accounts, ok := got["accounts"].([]any)
	if !ok {
		t.Fatalf("accounts missing from runtime settings: %#v", got)
	}
	if len(accounts) != 0 {
		t.Fatalf("noauth mixed should not project clients into accounts: %#v", accounts)
	}
	if got["auth"] != "noauth" || got["udp"] != true {
		t.Fatalf("protocol fields not preserved: %#v", got)
	}
}
