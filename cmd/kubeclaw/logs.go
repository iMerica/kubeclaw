package main

import (
	"fmt"

	"github.com/iMerica/kubeclaw/internal/kube"
	"github.com/spf13/cobra"
)

var (
	logsFollow    bool
	logsTail      int
	logsContainer string
)

var logsCmd = &cobra.Command{
	Use:   "logs",
	Short: "Tail OpenClaw Gateway logs",
	RunE: func(cmd *cobra.Command, args []string) error {
		podName := fmt.Sprintf("%s-gateway-0", release)
		return kube.TailLogs(namespace, podName, logsContainer, logsFollow, logsTail)
	},
}

func init() {
	logsCmd.Flags().BoolVarP(&logsFollow, "follow", "f", true, "Follow log output")
	logsCmd.Flags().IntVar(&logsTail, "tail", 100, "Number of recent lines to show")
	logsCmd.Flags().StringVarP(&logsContainer, "container", "c", "gateway", "Container name")
}
