package main

import (
	"fmt"
	"os"

	"github.com/iMerica/kubeclaw/internal/helm"
	"github.com/iMerica/kubeclaw/internal/kube"
	"github.com/iMerica/kubeclaw/internal/tui"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show current deployment status",
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println(tui.RenderLogo())

		helmClient := helm.NewClient(namespace, kubeconfig)

		// Release info
		fmt.Println(tui.RenderSection("Release", 60))
		if !helmClient.ReleaseExists(release) {
			fmt.Printf("  %s Release %q not found in namespace %q\n",
				tui.BadgeFail, release, namespace)
			os.Exit(1)
		}
		fmt.Printf("  %s Release %q found in namespace %q\n",
			tui.BadgePass, release, namespace)

		// Pod status
		fmt.Println(tui.RenderSection("Components", 60))
		kubeClient, _, err := kube.NewClient(kubeconfig)
		if err != nil {
			fmt.Printf("  %s Cannot connect to cluster: %s\n", tui.BadgeFail, err)
			os.Exit(1)
		}

		label := fmt.Sprintf("app.kubernetes.io/instance=%s", release)
		pods, err := kube.ListPods(kubeClient, namespace, label)
		if err != nil {
			fmt.Printf("  %s Failed to list pods: %s\n", tui.BadgeFail, err)
		} else {
			var rows [][]string
			for _, p := range pods {
				readyStr := tui.Error.Render("Not Ready")
				if p.Ready {
					readyStr = tui.Success.Render("Ready")
				}
				rows = append(rows, []string{p.Name, p.Phase, readyStr, fmt.Sprintf("%d", p.Restarts)})
			}
			if len(rows) > 0 {
				fmt.Println(tui.RenderTable(
					[]string{"Pod", "Phase", "Status", "Restarts"},
					rows,
				))
			} else {
				fmt.Printf("  %s No pods found\n", tui.BadgeWarn)
			}
		}

		// PVC status
		fmt.Println(tui.RenderSection("Persistent Volumes", 60))
		pvcs, err := kube.GetPVCStatus(kubeClient, namespace, "")
		if err == nil && len(pvcs) > 0 {
			var pvcRows [][]string
			for _, pvc := range pvcs {
				statusStr := tui.Warning.Render(pvc.Status)
				if pvc.Status == "Bound" {
					statusStr = tui.Success.Render("Bound")
				}
				pvcRows = append(pvcRows, []string{pvc.Name, statusStr, pvc.Capacity})
			}
			fmt.Println(tui.RenderTable(
				[]string{"PVC", "Status", "Capacity"},
				pvcRows,
			))
		} else {
			fmt.Printf("  %s No PVCs found\n", tui.BadgeWarn)
		}

		// Gateway API
		fmt.Println(tui.RenderSection("Gateway API", 60))
		dynClient, _, err := kube.NewDynamicClient(kubeconfig)
		if err == nil {
			gwName := fmt.Sprintf("%s-gateway-api", release)
			programmed, err := kube.IsGatewayProgrammed(dynClient, gwName, namespace)
			if err != nil {
				fmt.Printf("  %s Gateway API: %s\n", tui.BadgeWarn, err)
			} else if programmed {
				fmt.Printf("  %s Gateway %q is programmed\n", tui.BadgePass, gwName)
			} else {
				fmt.Printf("  %s Gateway %q is not yet programmed\n", tui.BadgeWarn, gwName)
			}

			// Routes
			routes, err := kube.GetHTTPRoutes(dynClient, namespace, label)
			if err == nil && len(routes) > 0 {
				fmt.Println()
				fmt.Println(tui.Muted.Render("  Routes:"))
				for _, r := range routes {
					fmt.Printf("    %s %s\n", tui.Primary.Render(r.Path), tui.Muted.Render(r.Name))
				}
			}
		}

		fmt.Println()
		return nil
	},
}
