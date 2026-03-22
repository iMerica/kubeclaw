package main

import (
	"fmt"
	"os"

	"github.com/iMerica/kubeclaw/internal/config"
	"github.com/iMerica/kubeclaw/internal/tui"
	"github.com/spf13/cobra"
)

var (
	namespace  string
	release    string
	kubeconfig string
	verbose    bool
)

var rootCmd = &cobra.Command{
	Use:   "kubeclaw",
	Short: "CLI for managing KubeClaw Helm chart installations",
	Long:  tui.RenderLogo(),
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		if verbose {
			fmt.Fprintf(os.Stderr, "%s kubeclaw %s (%s)\n",
				tui.Muted.Render("debug:"),
				config.Version, config.Commit)
		}
	},
}

func init() {
	rootCmd.PersistentFlags().StringVarP(&namespace, "namespace", "n", config.DefaultNamespace, "Kubernetes namespace")
	rootCmd.PersistentFlags().StringVarP(&release, "release", "r", config.DefaultRelease, "Helm release name")
	rootCmd.PersistentFlags().StringVar(&kubeconfig, "kubeconfig", "", "Path to kubeconfig (default: $KUBECONFIG or ~/.kube/config)")
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "Enable verbose output")

	rootCmd.AddCommand(versionCmd)
	rootCmd.AddCommand(installCmd)
	rootCmd.AddCommand(updateCmd)
	rootCmd.AddCommand(statusCmd)
	rootCmd.AddCommand(doctorCmd)
	rootCmd.AddCommand(destroyCmd)
	rootCmd.AddCommand(logsCmd)
	rootCmd.AddCommand(shellCmd)
	rootCmd.AddCommand(skillstackCmd)

	// Register colon-syntax aliases as top-level commands
	rootCmd.AddCommand(&cobra.Command{
		Use:    "skillstack:add",
		Short:  "Enable a SkillStack domain (alias for skillstack add)",
		Args:   cobra.ExactArgs(1),
		Hidden: true,
		RunE:   skillstackAddRunE,
	})
	rootCmd.AddCommand(&cobra.Command{
		Use:    "skillstack:remove",
		Short:  "Disable a SkillStack domain (alias for skillstack remove)",
		Args:   cobra.ExactArgs(1),
		Hidden: true,
		RunE:   skillstackRemoveRunE,
	})
	rootCmd.AddCommand(&cobra.Command{
		Use:    "skillstack:list",
		Short:  "List SkillStack domains (alias for skillstack list)",
		Hidden: true,
		RunE:   skillstackListRunE,
	})
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
