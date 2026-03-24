package helm

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

const commandTimeout = 15 * time.Minute

type Client struct {
	Namespace  string
	Kubeconfig string
}

func NewClient(namespace, kubeconfig string) *Client {
	return &Client{Namespace: namespace, Kubeconfig: kubeconfig}
}

func (c *Client) Install(releaseName, chartRef string, sets []string, valuesFiles []string, dryRun bool) error {
	args := []string{"upgrade", "--install", releaseName, chartRef,
		"--namespace", c.Namespace,
		"--wait", "--timeout", "10m",
	}
	if c.Kubeconfig != "" {
		args = append(args, "--kubeconfig", c.Kubeconfig)
	}
	for _, f := range valuesFiles {
		args = append(args, "-f", f)
	}
	for _, s := range sets {
		args = append(args, "--set", s)
	}
	if dryRun {
		args = append(args, "--dry-run")
	}
	return c.run(args...)
}

func (c *Client) Upgrade(releaseName, chartRef string, sets []string, reuseValues bool) error {
	args := []string{"upgrade", releaseName, chartRef,
		"--namespace", c.Namespace,
		"--wait", "--timeout", "10m",
	}
	if c.Kubeconfig != "" {
		args = append(args, "--kubeconfig", c.Kubeconfig)
	}
	if reuseValues {
		args = append(args, "--reuse-values")
	}
	for _, s := range sets {
		args = append(args, "--set", s)
	}
	return c.run(args...)
}

func (c *Client) Uninstall(releaseName string, noHooks bool) error {
	args := []string{"uninstall", releaseName,
		"--namespace", c.Namespace,
		"--wait", "--timeout", "60s",
	}
	if c.Kubeconfig != "" {
		args = append(args, "--kubeconfig", c.Kubeconfig)
	}
	if noHooks {
		args = append(args, "--no-hooks")
	}
	return c.run(args...)
}

func (c *Client) GetValues(releaseName string) (string, error) {
	args := []string{"get", "values", releaseName,
		"--namespace", c.Namespace,
		"--all", "-o", "yaml",
	}
	if c.Kubeconfig != "" {
		args = append(args, "--kubeconfig", c.Kubeconfig)
	}
	cmd := exec.Command("helm", args...)
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("helm get values failed: %w", err)
	}
	return string(out), nil
}

func (c *Client) Status(releaseName string) (string, error) {
	args := []string{"status", releaseName,
		"--namespace", c.Namespace,
	}
	if c.Kubeconfig != "" {
		args = append(args, "--kubeconfig", c.Kubeconfig)
	}
	cmd := exec.Command("helm", args...)
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("helm status failed: %w", err)
	}
	return string(out), nil
}

func (c *Client) ReleaseExists(releaseName string) bool {
	args := []string{"status", releaseName,
		"--namespace", c.Namespace,
	}
	if c.Kubeconfig != "" {
		args = append(args, "--kubeconfig", c.Kubeconfig)
	}
	cmd := exec.Command("helm", args...)
	return cmd.Run() == nil
}

func (c *Client) ShowChartVersion(chartRef string) (string, error) {
	args := []string{"show", "chart", chartRef}
	cmd := exec.Command("helm", args...)
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("helm show chart failed: %w", err)
	}
	for _, line := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(line, "version:") {
			return strings.TrimSpace(strings.TrimPrefix(line, "version:")), nil
		}
	}
	return "unknown", nil
}

func (c *Client) run(args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), commandTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "helm", args...)
	out, err := cmd.CombinedOutput()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return fmt.Errorf("helm command timed out after %s while running: helm %s", commandTimeout, strings.Join(args, " "))
	}
	if err != nil {
		if len(out) > 0 {
			return fmt.Errorf("%w\n%s", err, string(out))
		}
		return err
	}
	return nil
}
