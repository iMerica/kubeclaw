package main

import (
	"regexp"
	"testing"
)

func TestGenerateHexToken(t *testing.T) {
	token := generateHexToken(32)
	if len(token) != 64 {
		t.Fatalf("expected token length 64, got %d", len(token))
	}

	if !regexp.MustCompile(`^[0-9a-f]+$`).MatchString(token) {
		t.Fatalf("expected lowercase hex token, got %q", token)
	}
}

func TestGetEnvForProvider(t *testing.T) {
	t.Setenv("OPENAI_API_KEY", "openai-key")
	t.Setenv("ANTHROPIC_API_KEY", "anthropic-key")
	t.Setenv("OPENROUTER_API_KEY", "openrouter-key")

	tests := []struct {
		name     string
		provider string
		want     string
	}{
		{name: "openai", provider: "openai", want: "openai-key"},
		{name: "anthropic", provider: "anthropic", want: "anthropic-key"},
		{name: "openrouter", provider: "openrouter", want: "openrouter-key"},
		{name: "unknown", provider: "unknown", want: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := getEnvForProvider(tt.provider); got != tt.want {
				t.Fatalf("getEnvForProvider(%q) = %q, want %q", tt.provider, got, tt.want)
			}
		})
	}
}

func TestEnvKeyForProvider(t *testing.T) {
	tests := []struct {
		provider string
		want     string
	}{
		{provider: "openai", want: "OPENAI_API_KEY"},
		{provider: "anthropic", want: "ANTHROPIC_API_KEY"},
		{provider: "openrouter", want: "OPENROUTER_API_KEY"},
		{provider: "unknown", want: ""},
	}

	for _, tt := range tests {
		if got := envKeyForProvider(tt.provider); got != tt.want {
			t.Fatalf("envKeyForProvider(%q) = %q, want %q", tt.provider, got, tt.want)
		}
	}
}

func TestProviderLabel(t *testing.T) {
	tests := []struct {
		provider string
		want     string
	}{
		{provider: "openai", want: "OpenAI"},
		{provider: "anthropic", want: "Anthropic"},
		{provider: "openrouter", want: "OpenRouter"},
		{provider: "skip", want: "none"},
		{provider: "", want: "none"},
		{provider: "custom-provider", want: "custom-provider"},
	}

	for _, tt := range tests {
		if got := providerLabel(tt.provider); got != tt.want {
			t.Fatalf("providerLabel(%q) = %q, want %q", tt.provider, got, tt.want)
		}
	}
}

func TestFirstEnv(t *testing.T) {
	t.Setenv("FIRST_EMPTY", "")
	t.Setenv("SECOND_SET", "value")
	t.Setenv("THIRD_SET", "other")

	if got := firstEnv("FIRST_EMPTY", "SECOND_SET", "THIRD_SET"); got != "value" {
		t.Fatalf("firstEnv returned %q, want %q", got, "value")
	}

	if got := firstEnv("NOT_SET_A", "NOT_SET_B"); got != "" {
		t.Fatalf("firstEnv returned %q, want empty", got)
	}
}

func TestOrDefault(t *testing.T) {
	if got := orDefault("configured", "fallback"); got != "configured" {
		t.Fatalf("orDefault returned %q, want %q", got, "configured")
	}

	if got := orDefault("", "fallback"); got != "fallback" {
		t.Fatalf("orDefault returned %q, want %q", got, "fallback")
	}
}

func TestRedactSets(t *testing.T) {
	input := []string{
		"secret.data.OPENCLAW_GATEWAY_TOKEN=super-secret",
		"litellm.masterkey=sk-topsecret",
		"secret.data.OPENAI_API_KEY=provider-secret",
		"tailscale.ssh.authKey=tskey-auth-secret",
		"jira.auth.token=jira-secret",
		"trello.auth.apiKey=trello-secret",
		"regular.setting=true",
	}

	got := redactSets(input)
	want := []string{
		"secret.data.OPENCLAW_GATEWAY_TOKEN=****",
		"litellm.masterkey=****",
		"secret.data.OPENAI_API_KEY=****",
		"tailscale.ssh.authKey=****",
		"jira.auth.token=****",
		"trello.auth.apiKey=****",
		"regular.setting=true",
	}

	if len(got) != len(want) {
		t.Fatalf("redactSets length = %d, want %d", len(got), len(want))
	}

	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("redactSets[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}
