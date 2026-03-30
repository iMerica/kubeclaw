package main

import (
	"testing"

	"github.com/iMerica/kubeclaw/internal/config"
)

func TestRootCommandRegistersExpectedCommands(t *testing.T) {
	t.Helper()

	commands := make(map[string]bool)
	hidden := make(map[string]bool)
	for _, c := range rootCmd.Commands() {
		commands[c.Name()] = true
		hidden[c.Name()] = c.Hidden
	}

	expected := []string{
		"version",
		"install",
		"update",
		"status",
		"doctor",
		"destroy",
		"logs",
		"shell",
		"skillstack",
	}

	for _, name := range expected {
		if !commands[name] {
			t.Fatalf("expected command %q to be registered", name)
		}
	}

	aliases := []string{"skillstack:add", "skillstack:remove", "skillstack:list"}
	for _, name := range aliases {
		if !commands[name] {
			t.Fatalf("expected alias command %q to be registered", name)
		}
		if !hidden[name] {
			t.Fatalf("expected alias command %q to be hidden", name)
		}
	}
}

func TestRootCommandPersistentFlagDefaults(t *testing.T) {
	nsFlag := rootCmd.PersistentFlags().Lookup("namespace")
	if nsFlag == nil {
		t.Fatal("expected namespace flag")
	}
	if nsFlag.DefValue != config.DefaultNamespace {
		t.Fatalf("namespace default = %q, want %q", nsFlag.DefValue, config.DefaultNamespace)
	}

	relFlag := rootCmd.PersistentFlags().Lookup("release")
	if relFlag == nil {
		t.Fatal("expected release flag")
	}
	if relFlag.DefValue != config.DefaultRelease {
		t.Fatalf("release default = %q, want %q", relFlag.DefValue, config.DefaultRelease)
	}
}
