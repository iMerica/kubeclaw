package skillstack

import (
	"context"
	"fmt"

	"github.com/iMerica/kubeclaw/internal/helm"
)

func Add(ctx context.Context, helmClient *helm.Client, releaseName, chartRef, domainArg string) error {
	domain, err := FindDomain(domainArg)
	if err != nil {
		return err
	}
	set := fmt.Sprintf("skillStacks.%s.enabled=true", domain.Key)
	return helmClient.Upgrade(ctx, releaseName, chartRef, []string{set}, true)
}

func Remove(ctx context.Context, helmClient *helm.Client, releaseName, chartRef, domainArg string) error {
	domain, err := FindDomain(domainArg)
	if err != nil {
		return err
	}
	set := fmt.Sprintf("skillStacks.%s.enabled=false", domain.Key)
	return helmClient.Upgrade(ctx, releaseName, chartRef, []string{set}, true)
}
