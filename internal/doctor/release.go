package doctor

import (
	"context"
	"fmt"

	"github.com/iMerica/kubeclaw/internal/kube"
)

func init() {
	Register(Check{
		Name:     "release-exists",
		Category: "Release",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			if opts.HelmClient == nil {
				return Skip, "no Helm client available"
			}
			if !opts.HelmClient.ReleaseExists(opts.ReleaseName) {
				return Fail, fmt.Sprintf("release %q not found in namespace %q", opts.ReleaseName, opts.Namespace)
			}
			return Pass, fmt.Sprintf("release %q exists", opts.ReleaseName)
		},
	})

	Register(Check{
		Name:     "pods-running",
		Category: "Pods",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			if opts.KubeClient == nil {
				return Skip, "no Kubernetes client available"
			}
			label := fmt.Sprintf("app.kubernetes.io/instance=%s", opts.ReleaseName)
			pods, err := kube.ListPods(opts.KubeClient, opts.Namespace, label)
			if err != nil {
				return Fail, fmt.Sprintf("failed to list pods: %s", err)
			}
			if len(pods) == 0 {
				return Fail, "no pods found"
			}

			allReady := true
			totalRestarts := int32(0)
			for _, p := range pods {
				if !p.Ready {
					allReady = false
				}
				totalRestarts += p.Restarts
			}

			msg := fmt.Sprintf("%d pod(s) found", len(pods))
			if !allReady {
				return Warn, msg + " (not all ready)"
			}
			if totalRestarts > 0 {
				return Warn, fmt.Sprintf("%s, %d total restart(s)", msg, totalRestarts)
			}
			return Pass, msg + ", all ready"
		},
	})

	Register(Check{
		Name:     "gateway-pod",
		Category: "Pods",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			if opts.KubeClient == nil {
				return Skip, "no Kubernetes client available"
			}
			podName := fmt.Sprintf("%s-gateway-0", opts.ReleaseName)
			label := fmt.Sprintf("app.kubernetes.io/instance=%s,app.kubernetes.io/name=kubeclaw", opts.ReleaseName)
			pods, err := kube.ListPods(opts.KubeClient, opts.Namespace, label)
			if err != nil {
				return Fail, fmt.Sprintf("failed to check gateway pod: %s", err)
			}
			for _, p := range pods {
				if p.Name == podName {
					if p.Ready {
						return Pass, fmt.Sprintf("gateway pod %s is ready", podName)
					}
					return Warn, fmt.Sprintf("gateway pod %s exists but not ready (phase: %s)", podName, p.Phase)
				}
			}
			return Fail, fmt.Sprintf("gateway pod %s not found", podName)
		},
	})
}
