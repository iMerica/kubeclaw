package main

import (
	"fmt"

	"github.com/iMerica/kubeclaw/internal/kube"
	"github.com/spf13/cobra"
)

var shellContainer string

var shellCmd = &cobra.Command{
	Use:   "shell",
	Short: "Open a shell in the OpenClaw Gateway container",
	RunE: func(cmd *cobra.Command, args []string) error {
		podName := fmt.Sprintf("%s-gateway-0", release)
		return kube.ExecShell(namespace, podName, shellContainer)
	},
}

func init() {
	shellCmd.Flags().StringVarP(&shellContainer, "container", "c", "gateway", "Container name")
}
