package main

import (
	"context"
	"errors"
	"fmt"
	"os"

	"github.com/charmbracelet/huh"
	"github.com/iMerica/kubeclaw/internal/helm"
	"github.com/iMerica/kubeclaw/internal/kube"
	"github.com/iMerica/kubeclaw/internal/tui"
	"github.com/spf13/cobra"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var destroyYes bool

var destroyCmd = &cobra.Command{
	Use:   "destroy",
	Short: "Uninstall KubeClaw and clean up all resources",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		fmt.Println(tui.RenderLogo())
		fmt.Println(tui.RenderSection("Destroy KubeClaw", 60))
		fmt.Println()

		if !destroyYes {
			var confirm bool
			form := huh.NewForm(
				huh.NewGroup(
					huh.NewConfirm().
						Title(fmt.Sprintf("Permanently delete release %q and all data in namespace %q?", release, namespace)).
						Description("This will delete all PVCs and state. This action cannot be undone.").
						Affirmative("Yes, destroy").
						Negative("Cancel").
						Value(&confirm),
				),
			)
			if err := form.Run(); err != nil {
				return err
			}
			if !confirm {
				fmt.Println("  Cancelled.")
				return nil
			}
		}

		helmClient := helm.NewClient(namespace, kubeconfig)

		// Step 1: Strip finalizers from Gateway API resources
		fmt.Println()
		dynClient, _, _ := kube.NewDynamicClient(kubeconfig)
		if dynClient != nil {
			_ = tui.RunWithSpinner(ctx, "Stripping finalizers from Gateway API resources...", func(ctx context.Context) error {
				label := fmt.Sprintf("app.kubernetes.io/instance=%s", release)
				_ = kube.StripFinalizers(dynClient, metav1.GroupVersionResource{
					Group: "gateway.networking.k8s.io", Version: "v1", Resource: "gateways",
				}, namespace, label)
				_ = kube.StripFinalizers(dynClient, metav1.GroupVersionResource{
					Group: "gateway.networking.k8s.io", Version: "v1", Resource: "httproutes",
				}, namespace, label)
				return nil
			})
		}

		// Step 2: Helm uninstall
		err := tui.RunWithSpinner(ctx, "Running helm uninstall...", func(ctx context.Context) error {
			err := helmClient.Uninstall(ctx, release, false)
			if err != nil {
				// Retry with --no-hooks
				return helmClient.Uninstall(ctx, release, true)
			}
			return nil
		})
		if errors.Is(err, tui.ErrInterrupted) {
			fmt.Printf("\n  Interrupted. The uninstall may still be in progress.\n")
			fmt.Printf("  Check with: helm status %s -n %s\n\n", release, namespace)
			return nil
		}
		if err != nil {
			fmt.Printf("  %s Helm uninstall failed: %s\n", tui.BadgeWarn, err)
		}

		// Step 3: Clean up remaining resources
		kubeClient, _, _ := kube.NewClient(kubeconfig)
		if kubeClient != nil {
			_ = tui.RunWithSpinner(ctx, "Cleaning up remaining resources...", func(ctx context.Context) error {
				label := fmt.Sprintf("app.kubernetes.io/instance=%s", release)
				_ = kube.DeleteByLabel(kubeClient, namespace, label)
				_ = kube.DeleteClusterRolesByLabel(kubeClient, label)
				return nil
			})

			// Step 4: Delete PVCs
			_ = tui.RunWithSpinner(ctx, "Deleting persistent volume claims...", func(ctx context.Context) error {
				return kube.DeletePVCs(kubeClient, namespace, []string{
					"state-*",
					"workspace-*",
					"obsidian-*",
					"tailscale-*",
					"data-*",
				})
			})

			// Step 5: Try to delete envoy-gateway-system namespace
			_ = tui.RunWithSpinner(ctx, "Cleaning up Envoy Gateway system resources...", func(ctx context.Context) error {
				return kube.DeleteNamespace(kubeClient, "envoy-gateway-system")
			})
		}

		fmt.Println()
		fmt.Println(tui.RenderHR(60))
		fmt.Printf("  %s KubeClaw has been destroyed.\n", tui.Success.Render("✔"))
		fmt.Println()

		os.Exit(0)
		return nil
	},
}

func init() {
	destroyCmd.Flags().BoolVarP(&destroyYes, "yes", "y", false, "Skip confirmation prompt")
}
