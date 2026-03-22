package doctor

import (
	"context"
	"fmt"

	"github.com/iMerica/kubeclaw/internal/kube"
)

func init() {
	Register(Check{
		Name:     "pvcs-bound",
		Category: "Gateway",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			if opts.KubeClient == nil {
				return Skip, "no Kubernetes client available"
			}
			pvcs, err := kube.GetPVCStatus(opts.KubeClient, opts.Namespace, "")
			if err != nil {
				return Warn, fmt.Sprintf("failed to check PVCs: %s", err)
			}
			if len(pvcs) == 0 {
				return Warn, "no PVCs found"
			}
			allBound := true
			for _, pvc := range pvcs {
				if pvc.Status != "Bound" {
					allBound = false
				}
			}
			if !allBound {
				return Warn, fmt.Sprintf("%d PVC(s), not all bound", len(pvcs))
			}
			return Pass, fmt.Sprintf("%d PVC(s), all bound", len(pvcs))
		},
	})
}
