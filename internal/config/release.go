package config

type IntegrationConfig struct {
	GitHubToken  string
	JiraToken    string
	LinearToken  string
	AsanaPAT     string
	TrelloAPIKey string
	TrelloToken  string
}

type ReleaseConfig struct {
	Namespace      string
	ReleaseName    string
	GatewayToken   string
	LiteLLMMasterKey string
	LLMProvider    string // "openai", "anthropic", "openrouter", ""
	ProviderAPIKey string
	TailscaleEnabled bool
	TailscaleAuthKey string
	Integrations   IntegrationConfig
	SkillStacks    map[string]bool // domain key -> enabled
	ObsidianEnabled  bool
	ObsidianSize     string
	StorageClass     string
	PersistenceSize  string
}

func NewDefaultReleaseConfig() *ReleaseConfig {
	stacks := make(map[string]bool)
	stacks["platformEngineering"] = true
	stacks["devops"] = true
	stacks["sre"] = true
	stacks["swe"] = true
	stacks["qa"] = true
	stacks["marketing"] = true

	return &ReleaseConfig{
		Namespace:       DefaultNamespace,
		ReleaseName:     DefaultRelease,
		SkillStacks:     stacks,
		ObsidianEnabled: true,
		ObsidianSize:    "5Gi",
		PersistenceSize: "5Gi",
	}
}
