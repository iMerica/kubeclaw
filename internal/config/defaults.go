package config

var (
	Version = "dev"
	Commit  = "none"
)

const (
	DefaultNamespace = "kubeclaw"
	DefaultRelease   = "kubeclaw"
	ChartRef         = "oci://ghcr.io/imerica/kubeclaw"
	GatewayPort      = 18789
	BridgePort       = 18790
	CDPPort          = 9222
	LiteLLMPort      = 4000
	DefaultLocalPort = 8080
	StatePath        = "/home/node/.openclaw"
)
