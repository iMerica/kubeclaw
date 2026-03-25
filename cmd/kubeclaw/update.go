package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/charmbracelet/huh"
	"github.com/iMerica/kubeclaw/internal/config"
	"github.com/iMerica/kubeclaw/internal/helm"
	"github.com/iMerica/kubeclaw/internal/tui"
	"github.com/spf13/cobra"
)

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update an existing KubeClaw installation",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		fmt.Println(tui.RenderLogo())
		fmt.Println(tui.RenderSection("Update KubeClaw", 60))
		fmt.Println()

		helmClient := helm.NewClient(namespace, kubeconfig)

		if !helmClient.ReleaseExists(release) {
			fmt.Printf("  %s Release %q not found in namespace %q\n",
				tui.BadgeFail, release, namespace)
			fmt.Println("  Run 'kubeclaw install' to create a new installation.")
			return fmt.Errorf("release not found")
		}

		fmt.Printf("  %s Release %q found\n", tui.BadgePass, release)
		fmt.Println()

		var updateType string
		form := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("What would you like to update?").
					Options(
						huh.NewOption("LLM provider / API keys", "llm"),
						huh.NewOption("Integration tokens (GitHub, Jira, etc.)", "integrations"),
						huh.NewOption("SkillStacks", "skillstacks"),
						huh.NewOption("Tailscale configuration", "tailscale"),
						huh.NewOption("Storage settings", "storage"),
						huh.NewOption("Full chart upgrade (latest version)", "chart"),
					).
					Value(&updateType),
			),
		)
		if err := form.Run(); err != nil {
			return err
		}

		var sets []string

		switch updateType {
		case "llm":
			sets = promptLLMUpdate()
		case "integrations":
			sets = promptIntegrationUpdate()
		case "skillstacks":
			sets = promptSkillStackUpdate()
		case "tailscale":
			sets = promptTailscaleUpdate()
		case "storage":
			sets = promptStorageUpdate()
		case "chart":
			// Just upgrade with no additional sets
		}

		if len(sets) == 0 && updateType != "chart" {
			fmt.Println("  No changes selected.")
			return nil
		}

		confirm := true
		confirmForm := huh.NewForm(
			huh.NewGroup(
				huh.NewConfirm().
					Title("Apply these changes?").
					Affirmative("Yes").
					Negative("Cancel").
					Value(&confirm),
			),
		)
		if err := confirmForm.Run(); err != nil {
			return err
		}
		if !confirm {
			fmt.Println("  Cancelled.")
			return nil
		}

		err := tui.RunWithSpinner(ctx, "Upgrading release...", func(ctx context.Context) error {
			return helmClient.Upgrade(ctx, release, config.ChartRef, sets, true)
		})
		if errors.Is(err, tui.ErrInterrupted) {
			fmt.Printf("\n  Interrupted. The upgrade may still be in progress.\n")
			fmt.Printf("  Check with: helm status %s -n %s\n\n", release, namespace)
			return nil
		}
		if err != nil {
			return fmt.Errorf("upgrade failed: %w", err)
		}

		fmt.Printf("\n  %s Update complete.\n\n", tui.Success.Render("✔"))
		return nil
	},
}

func promptLLMUpdate() []string {
	var provider string
	var apiKey string

	form := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("LLM Provider").
				Options(
					huh.NewOption("OpenAI", "openai"),
					huh.NewOption("Anthropic", "anthropic"),
					huh.NewOption("OpenRouter", "openrouter"),
				).
				Value(&provider),
			huh.NewInput().
				Title("API Key").
				EchoMode(huh.EchoModePassword).
				Value(&apiKey),
		),
	)
	if err := form.Run(); err != nil || apiKey == "" {
		return nil
	}

	var sets []string
	switch provider {
	case "openai":
		sets = append(sets, "secret.data.OPENAI_API_KEY="+apiKey)
	case "anthropic":
		sets = append(sets, "secret.data.ANTHROPIC_API_KEY="+apiKey)
	case "openrouter":
		sets = append(sets, "secret.data.OPENROUTER_API_KEY="+apiKey)
	}
	return sets
}

func promptIntegrationUpdate() []string {
	var githubToken, jiraToken, linearToken, asanaPAT, trelloKey string

	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().Title("GitHub token (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&githubToken),
			huh.NewInput().Title("Jira API token (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&jiraToken),
			huh.NewInput().Title("Linear API key (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&linearToken),
			huh.NewInput().Title("Asana PAT (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&asanaPAT),
			huh.NewInput().Title("Trello API key (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&trelloKey),
		),
	)
	if err := form.Run(); err != nil {
		return nil
	}

	var sets []string
	if githubToken != "" {
		sets = append(sets, "github.auth.token="+githubToken)
	}
	if jiraToken != "" {
		sets = append(sets, "jira.auth.token="+jiraToken)
	}
	if linearToken != "" {
		sets = append(sets, "linear.auth.token="+linearToken)
	}
	if asanaPAT != "" {
		sets = append(sets, "asana.auth.token="+asanaPAT)
	}
	if trelloKey != "" {
		sets = append(sets, "trello.auth.apiKey="+trelloKey)
	}
	return sets
}

func promptSkillStackUpdate() []string {
	options := make([]huh.Option[string], 0)
	for _, d := range config.NewDefaultReleaseConfig().SkillStacks {
		_ = d
	}
	// Use skillstack domains directly
	type domainInfo struct{ key, label string }
	domains := []domainInfo{
		{"platformEngineering", "Platform Engineering (K8s, Helm, IaC, monitoring)"},
		{"devops", "DevOps (CI/CD, containers, infrastructure)"},
		{"sre", "SRE (reliability, incidents, SLOs)"},
		{"swe", "Software Engineering (code review, architecture)"},
		{"qa", "QA (test planning, automation, regression)"},
		{"marketing", "Marketing (content, campaigns, analytics)"},
	}
	for _, d := range domains {
		options = append(options, huh.NewOption(d.label, d.key))
	}

	var selected []string
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewMultiSelect[string]().
				Title("Select SkillStacks to enable").
				Options(options...).
				Value(&selected),
		),
	)
	if err := form.Run(); err != nil {
		return nil
	}

	// Build sets: enable selected, disable unselected
	selectedMap := make(map[string]bool)
	for _, s := range selected {
		selectedMap[s] = true
	}

	var sets []string
	for _, d := range domains {
		if selectedMap[d.key] {
			sets = append(sets, fmt.Sprintf("skillStacks.%s.enabled=true", d.key))
		} else {
			sets = append(sets, fmt.Sprintf("skillStacks.%s.enabled=false", d.key))
		}
	}
	return sets
}

func promptTailscaleUpdate() []string {
	var enabled bool
	var authKey string

	form := huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().
				Title("Enable Tailscale SSH + tailnet exposure?").
				Value(&enabled),
		),
	)
	if err := form.Run(); err != nil {
		return nil
	}

	if !enabled {
		return []string{"tailscale.ssh.enabled=false", "tailscale.expose.enabled=false"}
	}

	keyForm := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Tailscale auth key (tskey-auth-...)").
				EchoMode(huh.EchoModePassword).
				Value(&authKey),
		),
	)
	if err := keyForm.Run(); err != nil || authKey == "" {
		return nil
	}

	return []string{
		"tailscale.ssh.enabled=true",
		"tailscale.expose.enabled=true",
		"tailscale.ssh.authKey=" + authKey,
	}
}

func promptStorageUpdate() []string {
	var size string
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Persistence size").
				Placeholder("5Gi").
				Value(&size),
		),
	)
	if err := form.Run(); err != nil || size == "" {
		return nil
	}
	return []string{"persistence.size=" + size}
}
