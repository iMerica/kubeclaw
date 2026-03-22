package helm

import (
	"github.com/iMerica/kubeclaw/internal/config"
)

func BuildInstallSets(cfg *config.ReleaseConfig) []string {
	var sets []string

	// Required
	sets = append(sets, "secret.create=true")
	sets = append(sets, "secret.data.OPENCLAW_GATEWAY_TOKEN="+cfg.GatewayToken)
	sets = append(sets, "litellm.masterkey="+cfg.LiteLLMMasterKey)

	// Persistence
	if cfg.PersistenceSize != "" {
		sets = append(sets, "persistence.size="+cfg.PersistenceSize)
	}
	if cfg.StorageClass != "" {
		sets = append(sets, "persistence.storageClass="+cfg.StorageClass)
	}

	// LLM provider keys
	switch cfg.LLMProvider {
	case "openai":
		if cfg.ProviderAPIKey != "" {
			sets = append(sets, "secret.data.OPENAI_API_KEY="+cfg.ProviderAPIKey)
		}
	case "anthropic":
		if cfg.ProviderAPIKey != "" {
			sets = append(sets, "secret.data.ANTHROPIC_API_KEY="+cfg.ProviderAPIKey)
		}
	case "openrouter":
		if cfg.ProviderAPIKey != "" {
			sets = append(sets, "secret.data.OPENROUTER_API_KEY="+cfg.ProviderAPIKey)
		}
	}

	// Tailscale
	if cfg.TailscaleEnabled {
		sets = append(sets, "tailscale.ssh.authKey="+cfg.TailscaleAuthKey)
	} else {
		sets = append(sets, "tailscale.ssh.enabled=false")
		sets = append(sets, "tailscale.expose.enabled=false")
	}

	// Integrations
	if cfg.Integrations.GitHubToken != "" {
		sets = append(sets, "github.auth.token="+cfg.Integrations.GitHubToken)
	}
	if cfg.Integrations.JiraToken != "" {
		sets = append(sets, "jira.auth.token="+cfg.Integrations.JiraToken)
	}
	if cfg.Integrations.LinearToken != "" {
		sets = append(sets, "linear.auth.token="+cfg.Integrations.LinearToken)
	}
	if cfg.Integrations.AsanaPAT != "" {
		sets = append(sets, "asana.auth.token="+cfg.Integrations.AsanaPAT)
	}
	if cfg.Integrations.TrelloAPIKey != "" {
		sets = append(sets, "trello.auth.apiKey="+cfg.Integrations.TrelloAPIKey)
	}
	if cfg.Integrations.TrelloToken != "" {
		sets = append(sets, "trello.auth.token="+cfg.Integrations.TrelloToken)
	}

	// SkillStacks: disable any that are false
	for key, enabled := range cfg.SkillStacks {
		if !enabled {
			sets = append(sets, "skillStacks."+key+".enabled=false")
		}
	}

	// Obsidian
	if !cfg.ObsidianEnabled {
		sets = append(sets, "obsidian.enabled=false")
	} else if cfg.ObsidianSize != "" {
		sets = append(sets, "obsidian.persistence.size="+cfg.ObsidianSize)
	}

	return sets
}
