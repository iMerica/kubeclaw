package kube

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

type PodInfo struct {
	Name       string
	Phase      string
	Ready      bool
	Restarts   int32
	Containers []ContainerInfo
}

type ContainerInfo struct {
	Name  string
	Ready bool
	State string
}

func ListPods(client kubernetes.Interface, namespace, labelSelector string) ([]PodInfo, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pods, err := client.CoreV1().Pods(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list pods: %w", err)
	}

	var result []PodInfo
	for _, pod := range pods.Items {
		info := PodInfo{
			Name:  pod.Name,
			Phase: string(pod.Status.Phase),
		}
		for _, cond := range pod.Status.Conditions {
			if cond.Type == "Ready" && cond.Status == "True" {
				info.Ready = true
			}
		}
		for _, cs := range pod.Status.ContainerStatuses {
			ci := ContainerInfo{
				Name:  cs.Name,
				Ready: cs.Ready,
			}
			if cs.State.Running != nil {
				ci.State = "Running"
			} else if cs.State.Waiting != nil {
				ci.State = cs.State.Waiting.Reason
			} else if cs.State.Terminated != nil {
				ci.State = cs.State.Terminated.Reason
			}
			info.Containers = append(info.Containers, ci)
			info.Restarts += cs.RestartCount
		}
		result = append(result, info)
	}
	return result, nil
}

func WaitPodReady(ctx context.Context, client kubernetes.Interface, namespace, podName string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		reqCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		pod, err := client.CoreV1().Pods(namespace).Get(reqCtx, podName, metav1.GetOptions{})
		cancel()
		if err == nil {
			for _, cond := range pod.Status.Conditions {
				if cond.Type == "Ready" && cond.Status == "True" {
					return nil
				}
			}
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("pod %s not ready after %s", podName, timeout)
}

func WaitPodsReady(ctx context.Context, client kubernetes.Interface, namespace, labelSelector string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		reqCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		pods, err := client.CoreV1().Pods(namespace).List(reqCtx, metav1.ListOptions{LabelSelector: labelSelector})
		cancel()
		if err == nil && podsReady(pods.Items) {
			return nil
		}

		time.Sleep(2 * time.Second)
	}

	reqCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	pods, err := client.CoreV1().Pods(namespace).List(reqCtx, metav1.ListOptions{LabelSelector: labelSelector})
	if err != nil {
		return fmt.Errorf("pods for selector %q not ready after %s", labelSelector, timeout)
	}

	var nonReady []string
	for _, pod := range pods.Items {
		if isPodReadyOrCompleted(pod) {
			continue
		}
		nonReady = append(nonReady, fmt.Sprintf("%s(%s)", pod.Name, pod.Status.Phase))
	}
	if len(nonReady) == 0 {
		return fmt.Errorf("pods for selector %q not ready after %s", labelSelector, timeout)
	}

	return fmt.Errorf("pods for selector %q not ready after %s: %s", labelSelector, timeout, strings.Join(nonReady, ", "))
}

func podsReady(pods []corev1.Pod) bool {
	if len(pods) == 0 {
		return false
	}
	for _, pod := range pods {
		if !isPodReadyOrCompleted(pod) {
			return false
		}
	}
	return true
}

func isPodReadyOrCompleted(pod corev1.Pod) bool {
	if pod.DeletionTimestamp != nil {
		return false
	}
	if pod.Status.Phase == corev1.PodSucceeded {
		return true
	}
	if pod.Status.Phase != corev1.PodRunning {
		return false
	}
	for _, cond := range pod.Status.Conditions {
		if cond.Type == corev1.PodReady {
			return cond.Status == corev1.ConditionTrue
		}
	}
	return false
}

func ExecShell(namespace, podName, container string) error {
	args := []string{"exec", "-it", podName, "-n", namespace, "-c", container, "--", "/bin/sh"}
	cmd := exec.Command("kubectl", args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func TailLogs(namespace, podName, container string, follow bool, tail int) error {
	args := []string{"logs", podName, "-n", namespace, "-c", container}
	if follow {
		args = append(args, "-f")
	}
	if tail > 0 {
		args = append(args, fmt.Sprintf("--tail=%d", tail))
	}
	cmd := exec.Command("kubectl", args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func StartPortForward(namespace, svcName string, localPort, remotePort int) (*exec.Cmd, error) {
	args := []string{
		"port-forward", "-n", namespace,
		fmt.Sprintf("svc/%s", svcName),
		fmt.Sprintf("%d:%d", localPort, remotePort),
	}
	cmd := exec.Command("kubectl", args...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("failed to start port-forward: %w", err)
	}
	return cmd, nil
}
