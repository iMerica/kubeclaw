package skillstack

import "fmt"

type Domain struct {
	Key         string
	DirName     string
	Label       string
	Description string
}

var AllDomains = []Domain{
	{Key: "platformEngineering", DirName: "platform-engineering", Label: "Platform Engineering", Description: "K8s, Helm, IaC, monitoring"},
	{Key: "devops", DirName: "devops", Label: "DevOps", Description: "CI/CD, containers, infrastructure"},
	{Key: "sre", DirName: "sre", Label: "SRE", Description: "reliability, incidents, SLOs"},
	{Key: "swe", DirName: "swe", Label: "Software Engineering", Description: "code review, architecture"},
	{Key: "qa", DirName: "qa", Label: "QA", Description: "test planning, automation, regression"},
	{Key: "marketing", DirName: "marketing", Label: "Marketing", Description: "content, campaigns, analytics"},
}

func FindDomain(name string) (*Domain, error) {
	for _, d := range AllDomains {
		if d.Key == name || d.DirName == name || d.Label == name {
			return &d, nil
		}
	}
	return nil, fmt.Errorf("unknown SkillStack domain: %q (valid: platformEngineering, devops, sre, swe, qa, marketing)", name)
}

func DomainKeys() []string {
	keys := make([]string, len(AllDomains))
	for i, d := range AllDomains {
		keys[i] = d.Key
	}
	return keys
}
