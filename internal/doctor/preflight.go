package doctor

import (
	"context"
	"fmt"
	"os/exec"
	"strings"

	"github.com/iMerica/kubeclaw/internal/kube"
)

func init() {
	Register(Check{
		Name:     "kubectl",
		Category: "Preflight",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			path, err := exec.LookPath("kubectl")
			if err != nil {
				return Fail, "kubectl not found in PATH"
			}
			out, err := exec.Command("kubectl", "version", "--client", "-o", "json").Output()
			if err != nil {
				return Warn, fmt.Sprintf("kubectl found at %s but version check failed", path)
			}
			_ = out
			return Pass, "kubectl available"
		},
	})

	Register(Check{
		Name:     "helm",
		Category: "Preflight",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			_, err := exec.LookPath("helm")
			if err != nil {
				return Fail, "helm not found in PATH"
			}
			out, err := exec.Command("helm", "version", "--short").Output()
			if err != nil {
				return Warn, "helm found but version check failed"
			}
			version := strings.TrimSpace(string(out))
			if len(version) > 1 && version[0] == 'v' && version[1] >= '3' && version[1] <= '9' {
				return Pass, fmt.Sprintf("helm %s", version)
			}
			if len(version) > 1 && version[0] == 'v' && version[1] < '3' {
				return Fail, fmt.Sprintf("helm v3+ required (found %s)", version)
			}
			return Pass, fmt.Sprintf("helm %s", version)
		},
	})

	Register(Check{
		Name:     "cluster",
		Category: "Preflight",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			if opts.KubeClient == nil {
				return Fail, "no Kubernetes client available"
			}
			err := kube.CheckCluster(opts.KubeClient)
			if err != nil {
				return Fail, fmt.Sprintf("cluster unreachable: %s", err)
			}
			ctxName, cluster, _ := kube.CurrentContext(opts.Kubeconfig)
			if cluster != "" {
				return Pass, fmt.Sprintf("cluster reachable (context: %s, cluster: %s)", ctxName, cluster)
			}
			return Pass, fmt.Sprintf("cluster reachable (context: %s)", ctxName)
		},
	})
}
