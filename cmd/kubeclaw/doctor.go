package main

import (
	"context"
	"fmt"
	"os"

	"github.com/iMerica/kubeclaw/internal/doctor"
	"github.com/iMerica/kubeclaw/internal/helm"
	"github.com/iMerica/kubeclaw/internal/kube"
	"github.com/iMerica/kubeclaw/internal/tui"
	"github.com/spf13/cobra"
)

var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Run diagnostic health checks on your KubeClaw installation",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println(tui.RenderLogo())
		fmt.Println(tui.RenderSection("KubeClaw Doctor", 60))
		fmt.Println()

		ctx := context.Background()
		opts := doctor.CheckOpts{
			Namespace:   namespace,
			ReleaseName: release,
			Kubeconfig:  kubeconfig,
		}

		// Try to create clients (some checks work without them)
		kubeClient, _, err := kube.NewClient(kubeconfig)
		if err == nil {
			opts.KubeClient = kubeClient
		}
		dynClient, _, err := kube.NewDynamicClient(kubeconfig)
		if err == nil {
			opts.DynClient = dynClient
		}
		opts.HelmClient = helm.NewClient(namespace, kubeconfig)

		passed, failed, warned := doctor.RunAll(ctx, opts)

		fmt.Println()
		fmt.Println(tui.RenderHR(60))
		summary := fmt.Sprintf("  %s %d passed",
			tui.Success.Render("●"), passed)
		if failed > 0 {
			summary += fmt.Sprintf("  %s %d failed",
				tui.Error.Render("●"), failed)
		}
		if warned > 0 {
			summary += fmt.Sprintf("  %s %d warning(s)",
				tui.Warning.Render("●"), warned)
		}
		fmt.Println(summary)
		fmt.Println()

		if failed > 0 {
			os.Exit(1)
		}
		return nil
	},
}
