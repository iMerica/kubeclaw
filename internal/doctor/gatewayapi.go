package doctor

import (
	"context"
	"fmt"

	"github.com/iMerica/kubeclaw/internal/kube"
)

func init() {
	Register(Check{
		Name:     "gateway-api-programmed",
		Category: "Gateway API",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			if opts.DynClient == nil {
				return Skip, "no dynamic client available"
			}
			gwName := fmt.Sprintf("%s-gateway-api", opts.ReleaseName)
			programmed, err := kube.IsGatewayProgrammed(opts.DynClient, gwName, opts.Namespace)
			if err != nil {
				return Warn, fmt.Sprintf("gateway API %q not found or error: %s", gwName, err)
			}
			if !programmed {
				return Warn, fmt.Sprintf("gateway API %q exists but not programmed", gwName)
			}
			return Pass, fmt.Sprintf("gateway API %q is programmed", gwName)
		},
	})

	Register(Check{
		Name:     "httproutes",
		Category: "Networking",
		Run: func(ctx context.Context, opts CheckOpts) (CheckResult, string) {
			if opts.DynClient == nil {
				return Skip, "no dynamic client available"
			}
			label := fmt.Sprintf("app.kubernetes.io/instance=%s", opts.ReleaseName)
			routes, err := kube.GetHTTPRoutes(opts.DynClient, opts.Namespace, label)
			if err != nil {
				return Warn, fmt.Sprintf("failed to list HTTPRoutes: %s", err)
			}
			if len(routes) == 0 {
				return Warn, "no HTTPRoutes found"
			}
			return Pass, fmt.Sprintf("%d HTTPRoute(s) configured", len(routes))
		},
	})
}
