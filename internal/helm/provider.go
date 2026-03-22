package helm

import "os"

const anthropicValuesYAML = `litellm:
  proxy_config:
    model_list:
      - model_name: "claude-sonnet-4-20250514"
        litellm_params:
          model: "anthropic/claude-sonnet-4-20250514"
          api_key: "os.environ/ANTHROPIC_API_KEY"
    litellm_settings:
      drop_params: true
    router_settings:
      routing_strategy: "simple-shuffle"

config:
  desired: |
    {
      "gateway": { "mode": "local", "bind": "lan", "trustedProxies": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] },
      "browser": {
        "enabled": true,
        "defaultProfile": "default",
        "profiles": {
          "default": {
            "cdpUrl": "http://kubeclaw-chromium:9222",
            "color": "#4285F4"
          }
        }
      },
      "models": {
        "mode": "merge",
        "providers": {
          "litellm": {
            "baseUrl": "http://kubeclaw-litellm:4000",
            "apiKey": "${LITELLM_API_KEY}",
            "api": "openai-completions",
            "models": [
              {
                "id": "claude-sonnet-4-20250514",
                "name": "Claude Sonnet 4",
                "reasoning": false,
                "input": ["text", "image"],
                "contextWindow": 200000,
                "maxTokens": 16384
              }
            ]
          }
        }
      },
      "agents": {
        "defaults": {
          "workspace": "/home/node/.openclaw/workspace",
          "model": {
            "primary": "litellm/claude-sonnet-4-20250514"
          },
          "userTimezone": "UTC",
          "timeoutSeconds": 600,
          "maxConcurrent": 1
        }
      }
    }
`

const openrouterValuesYAML = `litellm:
  proxy_config:
    model_list:
      - model_name: "claude-sonnet-4-20250514"
        litellm_params:
          model: "openrouter/anthropic/claude-sonnet-4-20250514"
          api_key: "os.environ/OPENROUTER_API_KEY"
    litellm_settings:
      drop_params: true
    router_settings:
      routing_strategy: "simple-shuffle"

config:
  desired: |
    {
      "gateway": { "mode": "local", "bind": "lan", "trustedProxies": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] },
      "browser": {
        "enabled": true,
        "defaultProfile": "default",
        "profiles": {
          "default": {
            "cdpUrl": "http://kubeclaw-chromium:9222",
            "color": "#4285F4"
          }
        }
      },
      "models": {
        "mode": "merge",
        "providers": {
          "litellm": {
            "baseUrl": "http://kubeclaw-litellm:4000",
            "apiKey": "${LITELLM_API_KEY}",
            "api": "openai-completions",
            "models": [
              {
                "id": "claude-sonnet-4-20250514",
                "name": "Claude Sonnet 4",
                "reasoning": false,
                "input": ["text", "image"],
                "contextWindow": 200000,
                "maxTokens": 16384
              }
            ]
          }
        }
      },
      "agents": {
        "defaults": {
          "workspace": "/home/node/.openclaw/workspace",
          "model": {
            "primary": "litellm/claude-sonnet-4-20250514"
          },
          "userTimezone": "UTC",
          "timeoutSeconds": 600,
          "maxConcurrent": 1
        }
      }
    }
`

func WriteProviderValuesFile(provider string) (string, error) {
	var content string
	switch provider {
	case "anthropic":
		content = anthropicValuesYAML
	case "openrouter":
		content = openrouterValuesYAML
	default:
		return "", nil // OpenAI uses chart defaults, no overlay needed
	}

	f, err := os.CreateTemp("", "kubeclaw-values-*.yaml")
	if err != nil {
		return "", err
	}
	if _, err := f.WriteString(content); err != nil {
		f.Close()
		os.Remove(f.Name())
		return "", err
	}
	f.Close()
	return f.Name(), nil
}
