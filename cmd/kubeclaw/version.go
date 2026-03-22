package main

import (
	"fmt"

	"github.com/iMerica/kubeclaw/internal/config"
	"github.com/iMerica/kubeclaw/internal/tui"
	"github.com/spf13/cobra"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print CLI version information",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("%s %s\n", tui.Bold.Render("kubeclaw"), config.Version)
		fmt.Printf("%s %s\n", tui.Muted.Render("commit:"), config.Commit)
		fmt.Printf("%s %s\n", tui.Muted.Render("chart:"), config.ChartRef)
	},
}
