package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/charmbracelet/huh"
	"github.com/iMerica/kubeclaw/internal/config"
	helmPkg "github.com/iMerica/kubeclaw/internal/helm"
	"github.com/iMerica/kubeclaw/internal/kube"
	"github.com/iMerica/kubeclaw/internal/tui"
	"github.com/spf13/cobra"
	"k8s.io/client-go/kubernetes"
)

var (
	installDryRun         bool
	installNonInteractive bool
)

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install KubeClaw on your Kubernetes cluster",
	Long:  "Interactive wizard that guides you through deploying KubeClaw. Mirrors all capabilities of the web installer.",
	RunE:  runInstall,
}

func init() {
	installCmd.Flags().BoolVar(&installDryRun, "dry-run", false, "Show computed helm command without executing")
	installCmd.Flags().BoolVar(&installNonInteractive, "non-interactive", false, "Skip interactive prompts, use defaults and environment variables")
}

func runInstall(cmd *cobra.Command, args []string) error {
	tui.PrintLogo()
	fmt.Println(tui.RenderHR(80))
	fmt.Printf("  %s\n", tui.White.Render("This installer will walk you through deploying KubeClaw on your cluster."))
	fmt.Printf("  %s\n", tui.Muted.Render("No permanent files are written to disk. All secrets are passed via --set flags."))
	fmt.Println(tui.RenderHR(80))

	// ── Preflight ──────────────────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Preflight Checks", 80))

	// kubectl
	if _, err := exec.LookPath("kubectl"); err != nil {
		fmt.Printf("  %s kubectl not found\n", tui.BadgeFail)
		return fmt.Errorf("install kubectl: https://kubernetes.io/docs/tasks/tools/")
	}
	fmt.Printf("  %s kubectl\n", tui.BadgePass)

	// helm
	helmOut, err := exec.Command("helm", "version", "--short").Output()
	if err != nil {
		fmt.Printf("  %s helm not found\n", tui.BadgeFail)
		return fmt.Errorf("install helm v3+: https://helm.sh/docs/intro/install/")
	}
	helmVersion := strings.TrimSpace(string(helmOut))
	if len(helmVersion) < 2 || helmVersion[0] != 'v' || helmVersion[1] < '3' {
		fmt.Printf("  %s helm v3+ required (found %s)\n", tui.BadgeFail, helmVersion)
		return fmt.Errorf("upgrade helm to v3+")
	}
	fmt.Printf("  %s helm %s\n", tui.BadgePass, helmVersion)

	// cluster
	kubeClient, _, err := kube.NewClient(kubeconfig)
	if err != nil {
		fmt.Printf("  %s cannot create Kubernetes client: %s\n", tui.BadgeFail, err)
		return fmt.Errorf("check your kubeconfig and cluster connectivity")
	}
	if err := kube.CheckCluster(kubeClient); err != nil {
		fmt.Printf("  %s cluster unreachable: %s\n", tui.BadgeFail, err)
		return err
	}
	fmt.Printf("  %s cluster reachable\n", tui.BadgePass)

	// context
	ctxName, clusterName, _ := kube.CurrentContext(kubeconfig)
	fmt.Printf("  %s Context: %s\n", tui.Muted.Render("  ▸"), tui.Bold.Render(ctxName))
	if clusterName != "" {
		fmt.Printf("  %s Cluster: %s\n", tui.Muted.Render("  ▸"), tui.Bold.Render(clusterName))
	}

	if !installNonInteractive {
		confirmCluster := true
		clusterForm := huh.NewForm(
			huh.NewGroup(
				huh.NewConfirm().
					Title("Is this the correct cluster?").
					Affirmative("Yes").
					Negative("No").
					Value(&confirmCluster),
			),
		)
		if err := clusterForm.Run(); err != nil {
			return err
		}
		if !confirmCluster {
			return fmt.Errorf("switch context with: kubectl config use-context <name>")
		}
	}

	// storage classes
	storageClasses, defaultSC, _ := kube.GetStorageClasses(kubeClient)
	if len(storageClasses) > 0 {
		fmt.Printf("  %s storage classes: %s\n", tui.BadgePass, strings.Join(storageClasses, ", "))
		if defaultSC != "" {
			fmt.Printf("  %s Default: %s\n", tui.Muted.Render("  ▸"), tui.Bold.Render(defaultSC))
		}
	} else {
		fmt.Printf("  %s no storage classes found\n", tui.BadgeSkip)
	}

	cfg := config.NewDefaultReleaseConfig()
	cfg.Namespace = namespace
	cfg.ReleaseName = release

	if installNonInteractive {
		return runNonInteractiveInstall(cfg, storageClasses)
	}

	// ── Step 1: Basic Settings ─────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Installation Settings", 80))

	basicForm := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Namespace").
				Value(&cfg.Namespace),
			huh.NewInput().
				Title("Release name").
				Value(&cfg.ReleaseName),
		),
	)
	if err := basicForm.Run(); err != nil {
		return err
	}

	// ── Step 2: LLM Provider ──────────────────────────────────────────────
	fmt.Println(tui.RenderSection("LLM Provider", 80))
	fmt.Printf("  %s\n", tui.Muted.Render("KubeClaw routes all LLM calls through a built-in LiteLLM proxy."))
	fmt.Printf("  %s\n\n", tui.Muted.Render("You need at least one provider API key."))

	var llmProvider string
	providerForm := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Which LLM provider?").
				Options(
					huh.NewOption("OpenAI", "openai"),
					huh.NewOption("Anthropic", "anthropic"),
					huh.NewOption("OpenRouter", "openrouter"),
					huh.NewOption("Skip (configure later)", "skip"),
				).
				Value(&llmProvider),
		),
	)
	if err := providerForm.Run(); err != nil {
		return err
	}

	cfg.LLMProvider = llmProvider
	if llmProvider != "skip" {
		apiKey := getEnvForProvider(llmProvider)
		if apiKey != "" {
			fmt.Printf("  %s Using %s from environment\n", tui.BadgePass, envKeyForProvider(llmProvider))
		} else {
			keyForm := huh.NewForm(
				huh.NewGroup(
					huh.NewInput().
						Title(fmt.Sprintf("%s API key", providerLabel(llmProvider))).
						EchoMode(huh.EchoModePassword).
						Value(&apiKey).
						Validate(func(s string) error {
							if s == "" {
								return fmt.Errorf("API key is required")
							}
							return nil
						}),
				),
			)
			if err := keyForm.Run(); err != nil {
				return err
			}
		}
		cfg.ProviderAPIKey = apiKey
	}

	// ── Step 3: Gateway Token ─────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Gateway Token", 80))
	fmt.Printf("  %s\n\n", tui.Muted.Render("The Gateway requires an auth token for health probes and API access."))

	envToken := os.Getenv("OPENCLAW_GATEWAY_TOKEN")
	if envToken != "" {
		cfg.GatewayToken = envToken
		fmt.Printf("  %s Using OPENCLAW_GATEWAY_TOKEN from environment\n", tui.BadgePass)
	} else {
		autoGen := true
		tokenForm := huh.NewForm(
			huh.NewGroup(
				huh.NewConfirm().
					Title("Auto-generate a secure token?").
					Affirmative("Yes").
					Negative("No, I'll provide one").
					Value(&autoGen),
			),
		)
		if err := tokenForm.Run(); err != nil {
			return err
		}
		if autoGen {
			cfg.GatewayToken = generateHexToken(32)
			fmt.Printf("  %s Generated token: %s...\n", tui.Success.Render("✔"), tui.Muted.Render(cfg.GatewayToken[:16]))
		} else {
			manualForm := huh.NewForm(
				huh.NewGroup(
					huh.NewInput().
						Title("Gateway token").
						EchoMode(huh.EchoModePassword).
						Value(&cfg.GatewayToken).
						Validate(func(s string) error {
							if s == "" {
								return fmt.Errorf("token is required")
							}
							return nil
						}),
				),
			)
			if err := manualForm.Run(); err != nil {
				return err
			}
		}
	}

	// ── Step 4: LiteLLM Master Key ────────────────────────────────────────
	fmt.Println(tui.RenderSection("LiteLLM Master Key", 80))
	fmt.Printf("  %s\n\n", tui.Muted.Render("The LiteLLM proxy requires a master key (must start with 'sk-')."))

	envLiteLLM := os.Getenv("LITELLM_MASTERKEY")
	if envLiteLLM != "" {
		cfg.LiteLLMMasterKey = envLiteLLM
		fmt.Printf("  %s Using LITELLM_MASTERKEY from environment\n", tui.BadgePass)
	} else {
		autoGen := true
		litellmForm := huh.NewForm(
			huh.NewGroup(
				huh.NewConfirm().
					Title("Auto-generate a master key?").
					Affirmative("Yes").
					Negative("No, I'll provide one").
					Value(&autoGen),
			),
		)
		if err := litellmForm.Run(); err != nil {
			return err
		}
		if autoGen {
			cfg.LiteLLMMasterKey = "sk-" + generateHexToken(16)
			fmt.Printf("  %s Generated key: %s...\n", tui.Success.Render("✔"), tui.Muted.Render(cfg.LiteLLMMasterKey[:12]))
		} else {
			manualForm := huh.NewForm(
				huh.NewGroup(
					huh.NewInput().
						Title("LiteLLM master key (sk-...)").
						EchoMode(huh.EchoModePassword).
						Value(&cfg.LiteLLMMasterKey).
						Validate(func(s string) error {
							if s == "" {
								return fmt.Errorf("master key is required")
							}
							if !strings.HasPrefix(s, "sk-") {
								return fmt.Errorf("must start with 'sk-'")
							}
							return nil
						}),
				),
			)
			if err := manualForm.Run(); err != nil {
				return err
			}
		}
	}

	// ── Step 5: Tailscale ─────────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Tailscale Integration", 80))
	fmt.Printf("  %s\n\n", tui.Muted.Render("Tailscale provides SSH access and tailnet exposure for your Gateway."))

	envTS := os.Getenv("TS_AUTHKEY")
	if envTS == "" {
		envTS = os.Getenv("TAILSCALE_AUTH_KEY")
	}
	if envTS != "" {
		cfg.TailscaleEnabled = true
		cfg.TailscaleAuthKey = envTS
		fmt.Printf("  %s Using Tailscale auth key from environment\n", tui.BadgePass)
	} else {
		cfg.TailscaleEnabled = true
		tsForm := huh.NewForm(
			huh.NewGroup(
				huh.NewConfirm().
					Title("Enable Tailscale SSH + tailnet exposure?").
					Affirmative("Yes").
					Negative("No").
					Value(&cfg.TailscaleEnabled),
			),
		)
		if err := tsForm.Run(); err != nil {
			return err
		}
		if cfg.TailscaleEnabled {
			keyForm := huh.NewForm(
				huh.NewGroup(
					huh.NewInput().
						Title("Tailscale auth key (tskey-auth-...)").
						EchoMode(huh.EchoModePassword).
						Value(&cfg.TailscaleAuthKey).
						Validate(func(s string) error {
							if s == "" {
								return fmt.Errorf("auth key is required when Tailscale is enabled")
							}
							return nil
						}),
				),
			)
			if err := keyForm.Run(); err != nil {
				return err
			}
		}
	}

	// ── Step 6: Integrations ──────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Integrations (optional)", 80))
	fmt.Printf("  %s\n\n", tui.Muted.Render("Configure API keys for GitHub, Jira, Linear, Asana, and Trello."))

	// Check environment
	cfg.Integrations.GitHubToken = firstEnv("GITHUB_TOKEN", "GH_TOKEN")
	cfg.Integrations.JiraToken = os.Getenv("JIRA_API_TOKEN")
	cfg.Integrations.LinearToken = os.Getenv("LINEAR_API_KEY")
	cfg.Integrations.AsanaPAT = os.Getenv("ASANA_PAT")
	cfg.Integrations.TrelloAPIKey = os.Getenv("TRELLO_API_KEY")
	cfg.Integrations.TrelloToken = os.Getenv("TRELLO_TOKEN")

	var detected []string
	if cfg.Integrations.GitHubToken != "" {
		detected = append(detected, "GitHub")
	}
	if cfg.Integrations.JiraToken != "" {
		detected = append(detected, "Jira")
	}
	if cfg.Integrations.LinearToken != "" {
		detected = append(detected, "Linear")
	}
	if cfg.Integrations.AsanaPAT != "" {
		detected = append(detected, "Asana")
	}
	if cfg.Integrations.TrelloAPIKey != "" {
		detected = append(detected, "Trello")
	}
	if len(detected) > 0 {
		fmt.Printf("  %s Detected from environment: %s\n", tui.BadgePass, strings.Join(detected, ", "))
	}

	var configureTools bool
	toolsForm := huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().
				Title("Configure integration API keys now?").
				Affirmative("Yes").
				Negative("No").
				Value(&configureTools),
		),
	)
	if err := toolsForm.Run(); err != nil {
		return err
	}
	if configureTools {
		intForm := huh.NewForm(
			huh.NewGroup(
				huh.NewInput().Title("GitHub token (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&cfg.Integrations.GitHubToken),
				huh.NewInput().Title("Jira API token (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&cfg.Integrations.JiraToken),
				huh.NewInput().Title("Linear API key (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&cfg.Integrations.LinearToken),
				huh.NewInput().Title("Asana PAT (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&cfg.Integrations.AsanaPAT),
				huh.NewInput().Title("Trello API key (Enter to skip)").EchoMode(huh.EchoModePassword).Value(&cfg.Integrations.TrelloAPIKey),
			),
		)
		if err := intForm.Run(); err != nil {
			return err
		}
		if cfg.Integrations.TrelloAPIKey != "" && cfg.Integrations.TrelloToken == "" {
			trelloForm := huh.NewForm(
				huh.NewGroup(
					huh.NewInput().Title("Trello token").EchoMode(huh.EchoModePassword).Value(&cfg.Integrations.TrelloToken),
				),
			)
			if err := trelloForm.Run(); err != nil {
				return err
			}
		}
	}

	// ── Step 7: SkillStacks ───────────────────────────────────────────────
	fmt.Println(tui.RenderSection("SkillStacks", 80))
	fmt.Printf("  %s\n", tui.Muted.Render("SkillStacks are curated collections of domain-specific skills."))
	fmt.Printf("  %s\n\n", tui.Muted.Render("Select which SkillStacks to install (all selected by default)."))

	type stackOption struct {
		key   string
		label string
	}
	stackDefs := []stackOption{
		{"platformEngineering", "Platform Engineering (K8s, Helm, IaC, monitoring)"},
		{"devops", "DevOps (CI/CD, containers, infrastructure)"},
		{"sre", "SRE (reliability, incidents, SLOs)"},
		{"swe", "Software Engineering (code review, architecture)"},
		{"qa", "QA (test planning, automation, regression)"},
		{"marketing", "Marketing (content, campaigns, analytics)"},
	}

	stackOptions := make([]huh.Option[string], len(stackDefs))
	allKeys := make([]string, len(stackDefs))
	for i, s := range stackDefs {
		stackOptions[i] = huh.NewOption(s.label, s.key)
		allKeys[i] = s.key
	}

	selectedStacks := make([]string, len(allKeys))
	copy(selectedStacks, allKeys)

	stackForm := huh.NewForm(
		huh.NewGroup(
			huh.NewMultiSelect[string]().
				Title("SkillStacks to install").
				Options(stackOptions...).
				Value(&selectedStacks),
		),
	)
	if err := stackForm.Run(); err != nil {
		return err
	}

	selectedMap := make(map[string]bool)
	for _, s := range selectedStacks {
		selectedMap[s] = true
	}
	for _, s := range stackDefs {
		cfg.SkillStacks[s.key] = selectedMap[s.key]
	}

	if len(selectedStacks) == len(stackDefs) {
		fmt.Printf("  %s All SkillStacks selected\n", tui.Success.Render("✔"))
	} else {
		fmt.Printf("  %s %d of %d SkillStacks selected\n", tui.Success.Render("✔"), len(selectedStacks), len(stackDefs))
	}

	// ── Step 8: Obsidian ──────────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Obsidian Vault", 80))
	fmt.Printf("  %s\n\n", tui.Muted.Render("KubeClaw can provision a persistent Markdown vault for the Obsidian skill."))

	obsForm := huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().
				Title("Enable Obsidian vault?").
				Affirmative("Yes").
				Negative("No").
				Value(&cfg.ObsidianEnabled),
		),
	)
	if err := obsForm.Run(); err != nil {
		return err
	}
	if cfg.ObsidianEnabled {
		sizeForm := huh.NewForm(
			huh.NewGroup(
				huh.NewInput().
					Title("Vault size").
					Placeholder("5Gi").
					Value(&cfg.ObsidianSize),
			),
		)
		if err := sizeForm.Run(); err != nil {
			return err
		}
	}

	// ── Step 9: Storage ───────────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Storage", 80))

	if len(storageClasses) > 0 {
		scOptions := make([]huh.Option[string], 0)
		for _, sc := range storageClasses {
			scOptions = append(scOptions, huh.NewOption(sc, sc))
		}
		scOptions = append(scOptions, huh.NewOption("(cluster default)", ""))

		scForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("Storage class for PVCs").
					Options(scOptions...).
					Value(&cfg.StorageClass),
				huh.NewInput().
					Title("OpenClaw storage volume size").
					Placeholder("5Gi").
					Value(&cfg.PersistenceSize),
			),
		)
		if err := scForm.Run(); err != nil {
			return err
		}
	} else {
		fmt.Printf("  %s No storage classes detected, using cluster default.\n", tui.Muted.Render("  ▸"))
		sizeForm := huh.NewForm(
			huh.NewGroup(
				huh.NewInput().
					Title("OpenClaw storage volume size").
					Placeholder("5Gi").
					Value(&cfg.PersistenceSize),
			),
		)
		if err := sizeForm.Run(); err != nil {
			return err
		}
	}

	// ── Review ────────────────────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Review", 80))

	tsStatus := tui.Error.Render("disabled")
	if cfg.TailscaleEnabled {
		tsStatus = tui.Success.Render("enabled")
	}
	obsStatus := tui.Error.Render("disabled")
	if cfg.ObsidianEnabled {
		obsStatus = fmt.Sprintf("%s (%s)", tui.Success.Render("enabled"), cfg.ObsidianSize)
	}

	stackCount := 0
	for _, v := range cfg.SkillStacks {
		if v {
			stackCount++
		}
	}

	pairs := [][]string{
		{"Namespace:", cfg.Namespace},
		{"Release:", cfg.ReleaseName},
		{"Chart:", config.ChartRef},
		{"LLM Provider:", providerLabel(cfg.LLMProvider)},
		{"Gateway Token:", cfg.GatewayToken[:min(16, len(cfg.GatewayToken))] + "..."},
		{"LiteLLM Key:", cfg.LiteLLMMasterKey[:min(12, len(cfg.LiteLLMMasterKey))] + "..."},
		{"Tailscale:", tsStatus},
		{"SkillStacks:", fmt.Sprintf("%d of %d enabled", stackCount, len(cfg.SkillStacks))},
		{"Obsidian Vault:", obsStatus},
		{"Storage Class:", orDefault(cfg.StorageClass, "cluster default")},
		{"OpenClaw Storage:", cfg.PersistenceSize},
	}
	fmt.Println(tui.RenderKeyValue(pairs))

	confirmInstall := true
	confirmForm := huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().
				Title("Proceed with installation?").
				Affirmative("Yes, install").
				Negative("Cancel").
				Value(&confirmInstall),
		),
	)
	if err := confirmForm.Run(); err != nil {
		return err
	}
	if !confirmInstall {
		return fmt.Errorf("installation cancelled")
	}

	return executeInstall(cmd.Context(), cfg, kubeClient)
}

func runNonInteractiveInstall(cfg *config.ReleaseConfig, storageClasses []string) error {
	// Populate from environment
	cfg.GatewayToken = os.Getenv("OPENCLAW_GATEWAY_TOKEN")
	if cfg.GatewayToken == "" {
		cfg.GatewayToken = generateHexToken(32)
	}
	cfg.LiteLLMMasterKey = os.Getenv("LITELLM_MASTERKEY")
	if cfg.LiteLLMMasterKey == "" {
		cfg.LiteLLMMasterKey = "sk-" + generateHexToken(16)
	}

	// LLM provider from env
	if key := os.Getenv("OPENAI_API_KEY"); key != "" {
		cfg.LLMProvider = "openai"
		cfg.ProviderAPIKey = key
	} else if key := os.Getenv("ANTHROPIC_API_KEY"); key != "" {
		cfg.LLMProvider = "anthropic"
		cfg.ProviderAPIKey = key
	} else if key := os.Getenv("OPENROUTER_API_KEY"); key != "" {
		cfg.LLMProvider = "openrouter"
		cfg.ProviderAPIKey = key
	}

	// Tailscale
	tsKey := firstEnv("TS_AUTHKEY", "TAILSCALE_AUTH_KEY")
	if tsKey != "" {
		cfg.TailscaleEnabled = true
		cfg.TailscaleAuthKey = tsKey
	} else {
		cfg.TailscaleEnabled = false
	}

	// Integrations
	cfg.Integrations.GitHubToken = firstEnv("GITHUB_TOKEN", "GH_TOKEN")
	cfg.Integrations.JiraToken = os.Getenv("JIRA_API_TOKEN")
	cfg.Integrations.LinearToken = os.Getenv("LINEAR_API_KEY")
	cfg.Integrations.AsanaPAT = os.Getenv("ASANA_PAT")
	cfg.Integrations.TrelloAPIKey = os.Getenv("TRELLO_API_KEY")
	cfg.Integrations.TrelloToken = os.Getenv("TRELLO_TOKEN")

	kubeClient, _, err := kube.NewClient(kubeconfig)
	if err != nil {
		return fmt.Errorf("cannot create Kubernetes client: %w", err)
	}

	return executeInstall(context.Background(), cfg, kubeClient)
}

func executeInstall(ctx context.Context, cfg *config.ReleaseConfig, kubeClient kubernetes.Interface) error {
	fmt.Println(tui.RenderSection("Installing KubeClaw", 80))

	// Create namespace
	err := tui.RunWithSpinner(ctx, "Creating namespace...", func(ctx context.Context) error {
		return kube.EnsureNamespace(kubeClient, cfg.Namespace)
	})
	if err != nil {
		return fmt.Errorf("failed to create namespace: %w", err)
	}

	// Build helm args
	sets := helmPkg.BuildInstallSets(cfg)
	var valuesFiles []string

	// Provider-specific values file
	providerFile, err := helmPkg.WriteProviderValuesFile(cfg.LLMProvider)
	if err != nil {
		return fmt.Errorf("failed to write provider values: %w", err)
	}
	if providerFile != "" {
		valuesFiles = append(valuesFiles, providerFile)
		defer func() {
			_ = os.Remove(providerFile)
		}()
	}

	if installDryRun {
		fmt.Println()
		fmt.Printf("  %s\n\n", tui.Muted.Render("Dry-run mode: helm command that would run:"))
		redacted := redactSets(sets)
		fmt.Printf("  helm upgrade --install %s %s \\\n", cfg.ReleaseName, config.ChartRef)
		fmt.Printf("    --namespace %s \\\n", cfg.Namespace)
		for _, f := range valuesFiles {
			fmt.Printf("    -f %s \\\n", f)
		}
		for _, s := range redacted {
			fmt.Printf("    --set %s \\\n", s)
		}
		fmt.Printf("    --timeout 10m\n\n")
		fmt.Printf("  %s Dry run complete. No changes were made.\n\n", tui.Success.Render("✔"))
		return nil
	}

	// Run helm install
	helmClient := helmPkg.NewClient(cfg.Namespace, kubeconfig)
	err = tui.RunWithSpinner(ctx, "Installing KubeClaw (this may take a few minutes)...", func(ctx context.Context) error {
		return helmClient.Install(ctx, cfg.ReleaseName, config.ChartRef, sets, valuesFiles, false)
	})
	if errors.Is(err, tui.ErrInterrupted) {
		fmt.Println()
		fmt.Printf("  Interrupted. The Helm release may still be progressing in-cluster.\n")
		fmt.Printf("  Check with: helm status %s -n %s\n", cfg.ReleaseName, cfg.Namespace)
		fmt.Printf("             kubectl get pods -n %s\n\n", cfg.Namespace)
		return nil
	}
	if err != nil {
		return fmt.Errorf("helm install failed: %w", err)
	}

	// ── Post-install ──────────────────────────────────────────────────────
	fmt.Println(tui.RenderSection("Post-Install", 80))

	// Wait for Gateway pod
	err = tui.RunWithSpinner(ctx, "Waiting for Gateway pod to become ready...", func(ctx context.Context) error {
		podName := fmt.Sprintf("%s-gateway-0", cfg.ReleaseName)
		return kube.WaitPodReady(ctx, kubeClient, cfg.Namespace, podName, 120*time.Second)
	})
	if errors.Is(err, tui.ErrInterrupted) {
		fmt.Printf("\n  Interrupted. The release is installed but pods may still be starting.\n")
		fmt.Printf("  Check with: kubectl get pods -n %s\n\n", cfg.Namespace)
		return nil
	}

	// Wait for Gateway API
	dynClient, _, _ := kube.NewDynamicClient(kubeconfig)
	if dynClient != nil {
		gwName := fmt.Sprintf("%s-gateway-api", cfg.ReleaseName)
		err = tui.RunWithSpinner(ctx, "Waiting for Gateway API to become programmed...", func(ctx context.Context) error {
			return kube.WaitGatewayProgrammed(ctx, dynClient, gwName, cfg.Namespace, 60*time.Second)
		})
		if errors.Is(err, tui.ErrInterrupted) {
			fmt.Printf("\n  Interrupted. The release is installed.\n")
			fmt.Printf("  Check with: kubectl get gateway -n %s\n\n", cfg.Namespace)
			return nil
		}

		// Discover Envoy proxy
		envoyName, envoyPort, err := kube.GetEnvoyProxyService(kubeClient, gwName, cfg.Namespace)
		if err == nil {
			fmt.Println()
			fmt.Printf("  %s Routes:\n", tui.Muted.Render("  ▸"))

			label := fmt.Sprintf("app.kubernetes.io/instance=%s", cfg.ReleaseName)
			routes, _ := kube.GetHTTPRoutes(dynClient, cfg.Namespace, label)
			localPort := config.DefaultLocalPort
			for _, r := range routes {
				if r.Path == "/litellm" || r.Path == "/filtering" {
					continue
				}
				fmt.Printf("    %s\n", tui.Primary.Render(fmt.Sprintf("http://localhost:%d%s", localPort, r.Path)))
			}

			// Port-forward offer
			if !installNonInteractive {
				fmt.Println()
				doForward := true
				pfForm := huh.NewForm(
					huh.NewGroup(
						huh.NewConfirm().
							Title("Start port-forward for local access?").
							Affirmative("Yes").
							Negative("No").
							Value(&doForward),
					),
				)
				if err := pfForm.Run(); err == nil && doForward {
					pfCmd, err := kube.StartPortForward(cfg.Namespace, envoyName, localPort, int(envoyPort))
					if err == nil {
						time.Sleep(2 * time.Second)
						if pfCmd.Process != nil {
							fmt.Printf("  %s Port-forward running (PID %d)\n", tui.Success.Render("✔"), pfCmd.Process.Pid)
							fmt.Println()
							url := fmt.Sprintf("http://localhost:%d/?token=%s", localPort, cfg.GatewayToken)
							fmt.Printf("  Open in your browser:\n")
							fmt.Printf("  %s\n", tui.Primary.Bold(true).Render(url))
							fmt.Println()
							fmt.Printf("  %s\n", tui.Muted.Render(fmt.Sprintf("Stop port-forward: kill %d", pfCmd.Process.Pid)))
						}
					}
				}
			}
		}
	}

	// Next steps
	fmt.Println()
	fmt.Println(tui.RenderSection("Next Steps", 80))
	fmt.Printf("  %s View logs:       kubectl logs -n %s %s-gateway-0 -c gateway -f\n", tui.Muted.Render("▸"), cfg.Namespace, cfg.ReleaseName)
	fmt.Printf("  %s Shell access:    kubectl exec -n %s -it %s-gateway-0 -c gateway -- sh\n", tui.Muted.Render("▸"), cfg.Namespace, cfg.ReleaseName)
	if cfg.TailscaleEnabled {
		fmt.Printf("  %s SSH access:      ssh %s-gateway (once Tailscale connects)\n", tui.Muted.Render("▸"), cfg.ReleaseName)
	}
	fmt.Printf("  %s Uninstall:       kubeclaw destroy\n", tui.Muted.Render("▸"))
	fmt.Printf("  %s Documentation:   https://kubeclaw.ai/docs\n", tui.Muted.Render("▸"))
	fmt.Println()
	fmt.Println(tui.RenderHR(80))
	fmt.Printf("  %s\n", tui.Success.Bold(true).Render("KubeClaw is ready. Happy building!"))
	fmt.Println(tui.RenderHR(80))
	fmt.Println()

	return nil
}

// ── Helpers ────────────────────────────────────────────────────────────────

func generateHexToken(bytes int) string {
	b := make([]byte, bytes)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func getEnvForProvider(provider string) string {
	switch provider {
	case "openai":
		return os.Getenv("OPENAI_API_KEY")
	case "anthropic":
		return os.Getenv("ANTHROPIC_API_KEY")
	case "openrouter":
		return os.Getenv("OPENROUTER_API_KEY")
	}
	return ""
}

func envKeyForProvider(provider string) string {
	switch provider {
	case "openai":
		return "OPENAI_API_KEY"
	case "anthropic":
		return "ANTHROPIC_API_KEY"
	case "openrouter":
		return "OPENROUTER_API_KEY"
	}
	return ""
}

func providerLabel(provider string) string {
	switch provider {
	case "openai":
		return "OpenAI"
	case "anthropic":
		return "Anthropic"
	case "openrouter":
		return "OpenRouter"
	case "skip", "":
		return "none"
	}
	return provider
}

func firstEnv(keys ...string) string {
	for _, k := range keys {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	return ""
}

func orDefault(val, def string) string {
	if val == "" {
		return def
	}
	return val
}

func redactSets(sets []string) []string {
	redacted := make([]string, len(sets))
	sensitiveKeys := []string{
		"OPENCLAW_GATEWAY_TOKEN=", "masterkey=", "API_KEY=",
		"authKey=", "auth.token=", "auth.apiKey=",
	}
	for i, s := range sets {
		isSensitive := false
		for _, key := range sensitiveKeys {
			if strings.Contains(s, key) {
				idx := strings.Index(s, "=")
				redacted[i] = s[:idx+1] + "****"
				isSensitive = true
				break
			}
		}
		if !isSensitive {
			redacted[i] = s
		}
	}
	return redacted
}
