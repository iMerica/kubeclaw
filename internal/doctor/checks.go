package doctor

import (
	"context"
	"fmt"

	"github.com/iMerica/kubeclaw/internal/helm"
	"github.com/iMerica/kubeclaw/internal/tui"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
)

type CheckResult int

const (
	Pass CheckResult = iota
	Fail
	Warn
	Skip
)

func (r CheckResult) Badge() string {
	switch r {
	case Pass:
		return tui.BadgePass
	case Fail:
		return tui.BadgeFail
	case Warn:
		return tui.BadgeWarn
	case Skip:
		return tui.BadgeSkip
	default:
		return tui.BadgeSkip
	}
}

type CheckOpts struct {
	Namespace   string
	ReleaseName string
	Kubeconfig  string
	KubeClient  kubernetes.Interface
	DynClient   dynamic.Interface
	HelmClient  *helm.Client
}

type Check struct {
	Name     string
	Category string
	Run      func(ctx context.Context, opts CheckOpts) (CheckResult, string)
}

var registry []Check

func Register(c Check) {
	registry = append(registry, c)
}

func AllChecks() []Check {
	return registry
}

func RunAll(ctx context.Context, opts CheckOpts) (passed, failed, warned int) {
	categories := []string{"Preflight", "Release", "Pods", "Gateway", "Networking", "Gateway API"}
	checksByCategory := make(map[string][]Check)
	for _, c := range registry {
		checksByCategory[c.Category] = append(checksByCategory[c.Category], c)
	}

	for _, cat := range categories {
		checks, ok := checksByCategory[cat]
		if !ok {
			continue
		}
		fmt.Println(tui.RenderSection(cat, 60))
		for _, c := range checks {
			result, msg := c.Run(ctx, opts)
			fmt.Printf("  %s %s", result.Badge(), msg)
			fmt.Println()
			switch result {
			case Pass:
				passed++
			case Fail:
				failed++
			case Warn:
				warned++
			}
		}
	}
	return passed, failed, warned
}
