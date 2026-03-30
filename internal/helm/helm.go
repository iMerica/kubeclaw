package helm

import (
	"context"
	"encoding/json"
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

func (c *Client) Install(ctx context.Context, releaseName, chartRef string, sets []string, valuesFiles []string, dryRun bool) error {
	args := []string{"upgrade", "--install", releaseName, chartRef,
		"--namespace", c.Namespace,
		"--wait=false",
		"--timeout", "10m",
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
	return c.runWithPendingRecovery(ctx, releaseName, args...)
}

func (c *Client) Upgrade(ctx context.Context, releaseName, chartRef string, sets []string, reuseValues bool) error {
	args := []string{"upgrade", releaseName, chartRef,
		"--namespace", c.Namespace,
		"--wait=false", "--timeout", "10m",
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
	return c.runWithPendingRecovery(ctx, releaseName, args...)
}

func (c *Client) Uninstall(ctx context.Context, releaseName string, noHooks bool) error {
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
	return c.run(ctx, args...)
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

func (c *Client) run(ctx context.Context, args ...string) error {
	ctx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "helm", args...)
	out, err := cmd.CombinedOutput()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return fmt.Errorf("helm command timed out after %s while running: helm %s", commandTimeout, strings.Join(args, " "))
	}
	if errors.Is(ctx.Err(), context.Canceled) {
		return context.Canceled
	}
	if err != nil {
		if len(out) > 0 {
			return fmt.Errorf("%w\n%s", err, string(out))
		}
		return err
	}
	return nil
}

func (c *Client) runWithPendingRecovery(ctx context.Context, releaseName string, args ...string) error {
	err := c.run(ctx, args...)
	if err == nil {
		return nil
	}
	if !isOperationInProgressError(err) {
		return err
	}

	if recoverErr := c.recoverPendingRelease(ctx, releaseName); recoverErr != nil {
		return fmt.Errorf("%w\nauto-recovery failed: %v", err, recoverErr)
	}

	if retryErr := c.run(ctx, args...); retryErr != nil {
		return fmt.Errorf("%w\nauto-recovery was attempted but retry still failed: %v", err, retryErr)
	}

	return nil
}

func (c *Client) recoverPendingRelease(ctx context.Context, releaseName string) error {
	history, err := c.history(ctx, releaseName)
	if err != nil {
		return err
	}

	revision := lastStableRevision(history)
	if revision == 0 {
		return fmt.Errorf("no stable revision found for %q", releaseName)
	}

	args := []string{"rollback", releaseName, fmt.Sprintf("%d", revision),
		"--namespace", c.Namespace,
		"--wait=false", "--timeout", "5m",
	}
	if c.Kubeconfig != "" {
		args = append(args, "--kubeconfig", c.Kubeconfig)
	}

	if err := c.run(ctx, args...); err != nil {
		return fmt.Errorf("rollback to revision %d failed: %w", revision, err)
	}

	return nil
}

type historyEntry struct {
	Revision int    `json:"revision"`
	Status   string `json:"status"`
}

func (c *Client) history(ctx context.Context, releaseName string) ([]historyEntry, error) {
	ctx, cancel := context.WithTimeout(ctx, commandTimeout)
	defer cancel()

	args := []string{"history", releaseName,
		"--namespace", c.Namespace,
		"-o", "json",
	}
	if c.Kubeconfig != "" {
		args = append(args, "--kubeconfig", c.Kubeconfig)
	}

	cmd := exec.CommandContext(ctx, "helm", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return nil, fmt.Errorf("helm history timed out after %s", commandTimeout)
		}
		if errors.Is(ctx.Err(), context.Canceled) {
			return nil, context.Canceled
		}
		if len(out) > 0 {
			return nil, fmt.Errorf("helm history failed: %w\n%s", err, string(out))
		}
		return nil, fmt.Errorf("helm history failed: %w", err)
	}

	var entries []historyEntry
	if err := json.Unmarshal(out, &entries); err != nil {
		return nil, fmt.Errorf("failed to parse helm history output: %w", err)
	}

	return entries, nil
}

func lastStableRevision(entries []historyEntry) int {
	for i := len(entries) - 1; i >= 0; i-- {
		status := strings.ToLower(entries[i].Status)
		if status == "deployed" || status == "superseded" {
			return entries[i].Revision
		}
	}
	return 0
}

func isOperationInProgressError(err error) bool {
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "another operation") && strings.Contains(msg, "in progress")
}
