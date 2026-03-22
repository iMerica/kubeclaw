package skillstack

import (
	"fmt"

	"github.com/iMerica/kubeclaw/internal/helm"
)

func Add(helmClient *helm.Client, releaseName, chartRef, domainArg string) error {
	domain, err := FindDomain(domainArg)
	if err != nil {
		return err
	}
	set := fmt.Sprintf("skillStacks.%s.enabled=true", domain.Key)
	return helmClient.Upgrade(releaseName, chartRef, []string{set}, true)
}

func Remove(helmClient *helm.Client, releaseName, chartRef, domainArg string) error {
	domain, err := FindDomain(domainArg)
	if err != nil {
		return err
	}
	set := fmt.Sprintf("skillStacks.%s.enabled=false", domain.Key)
	return helmClient.Upgrade(releaseName, chartRef, []string{set}, true)
}
