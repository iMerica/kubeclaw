package main

import (
	"fmt"
	"strings"

	"github.com/iMerica/kubeclaw/internal/config"
	"github.com/iMerica/kubeclaw/internal/helm"
	"github.com/iMerica/kubeclaw/internal/skillstack"
	"github.com/iMerica/kubeclaw/internal/tui"
	"github.com/spf13/cobra"
)

var skillstackCmd = &cobra.Command{
	Use:   "skillstack",
	Short: "Manage SkillStack domains",
	Long:  "Add, remove, or list SkillStack domains for your KubeClaw installation.",
}

func init() {
	skillstackCmd.AddCommand(&cobra.Command{
		Use:   "add <domain>",
		Short: "Enable a SkillStack domain",
		Args:  cobra.ExactArgs(1),
		RunE:  skillstackAddRunE,
	})
	skillstackCmd.AddCommand(&cobra.Command{
		Use:   "remove <domain>",
		Short: "Disable a SkillStack domain",
		Args:  cobra.ExactArgs(1),
		RunE:  skillstackRemoveRunE,
	})
	skillstackCmd.AddCommand(&cobra.Command{
		Use:   "list",
		Short: "List all SkillStack domains and their status",
		RunE:  skillstackListRunE,
	})
}

func skillstackAddRunE(cmd *cobra.Command, args []string) error {
	domain := args[0]
	d, err := skillstack.FindDomain(domain)
	if err != nil {
		return err
	}

	fmt.Printf("  Enabling SkillStack: %s\n", tui.Bold.Render(d.Label))

	helmClient := helm.NewClient(namespace, kubeconfig)
	err = tui.RunWithSpinner("Upgrading release...", func() error {
		return skillstack.Add(helmClient, release, config.ChartRef, domain)
	})
	if err != nil {
		return fmt.Errorf("failed to enable SkillStack %q: %w", d.Label, err)
	}
	fmt.Printf("  %s SkillStack %q enabled\n", tui.Success.Render("✔"), d.Label)
	return nil
}

func skillstackRemoveRunE(cmd *cobra.Command, args []string) error {
	domain := args[0]
	d, err := skillstack.FindDomain(domain)
	if err != nil {
		return err
	}

	fmt.Printf("  Disabling SkillStack: %s\n", tui.Bold.Render(d.Label))

	helmClient := helm.NewClient(namespace, kubeconfig)
	err = tui.RunWithSpinner("Upgrading release...", func() error {
		return skillstack.Remove(helmClient, release, config.ChartRef, domain)
	})
	if err != nil {
		return fmt.Errorf("failed to disable SkillStack %q: %w", d.Label, err)
	}
	fmt.Printf("  %s SkillStack %q disabled\n", tui.Success.Render("✔"), d.Label)
	return nil
}

func skillstackListRunE(cmd *cobra.Command, args []string) error {
	fmt.Println(tui.RenderSection("SkillStacks", 60))

	helmClient := helm.NewClient(namespace, kubeconfig)
	vals, err := helmClient.GetValues(release)

	var rows [][]string
	for _, d := range skillstack.AllDomains {
		status := tui.Success.Render("enabled")
		// Check if explicitly disabled in current values
		if err == nil && strings.Contains(vals, d.Key) {
			// Simple heuristic: if "enabled: false" appears near the domain key
			checkStr := d.Key + ":\n"
			idx := strings.Index(vals, checkStr)
			if idx >= 0 {
				section := vals[idx:]
				if strings.Contains(section[:min(len(section), 100)], "enabled: false") {
					status = tui.Error.Render("disabled")
				}
			}
		}
		rows = append(rows, []string{d.Key, status, d.Description})
	}

	if err != nil {
		// No release found, show defaults (all enabled)
		for i := range rows {
			rows[i][1] = tui.Muted.Render("default (enabled)")
		}
	}

	fmt.Println(tui.RenderTable(
		[]string{"Domain", "Status", "Description"},
		rows,
	))
	fmt.Println()
	fmt.Printf("  %s kubeclaw skillstack add <domain>    Enable a domain\n", tui.Muted.Render("Usage:"))
	fmt.Printf("  %s kubeclaw skillstack remove <domain> Disable a domain\n", tui.Muted.Render("      "))
	fmt.Println()
	return nil
}
