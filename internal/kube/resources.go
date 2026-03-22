package kube

import (
	"context"
	"fmt"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
)

func StripFinalizers(dynClient dynamic.Interface, gvr metav1.GroupVersionResource, namespace, labelSelector string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	resource := dynClient.Resource(toSchemaGVR(gvr)).Namespace(namespace)
	list, err := resource.List(ctx, metav1.ListOptions{LabelSelector: labelSelector})
	if err != nil {
		return nil // Resource type may not exist
	}
	patch := []byte(`{"metadata":{"finalizers":null}}`)
	for _, item := range list.Items {
		if len(item.GetFinalizers()) > 0 {
			_, err := resource.Patch(ctx, item.GetName(), types.MergePatchType, patch, metav1.PatchOptions{})
			if err != nil {
				return fmt.Errorf("failed to strip finalizers from %s/%s: %w", item.GetKind(), item.GetName(), err)
			}
		}
	}
	return nil
}

func DeleteByLabel(client kubernetes.Interface, namespace, labelSelector string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Delete deployments
	_ = client.AppsV1().Deployments(namespace).DeleteCollection(ctx,
		metav1.DeleteOptions{}, metav1.ListOptions{LabelSelector: labelSelector})
	// Delete statefulsets
	_ = client.AppsV1().StatefulSets(namespace).DeleteCollection(ctx,
		metav1.DeleteOptions{}, metav1.ListOptions{LabelSelector: labelSelector})
	// Delete services
	svcs, _ := client.CoreV1().Services(namespace).List(ctx, metav1.ListOptions{LabelSelector: labelSelector})
	if svcs != nil {
		for _, svc := range svcs.Items {
			_ = client.CoreV1().Services(namespace).Delete(ctx, svc.Name, metav1.DeleteOptions{})
		}
	}
	// Delete configmaps
	_ = client.CoreV1().ConfigMaps(namespace).DeleteCollection(ctx,
		metav1.DeleteOptions{}, metav1.ListOptions{LabelSelector: labelSelector})
	// Delete secrets
	_ = client.CoreV1().Secrets(namespace).DeleteCollection(ctx,
		metav1.DeleteOptions{}, metav1.ListOptions{LabelSelector: labelSelector})

	return nil
}

func DeletePVCs(client kubernetes.Interface, namespace string, patterns []string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	pvcs, err := client.CoreV1().PersistentVolumeClaims(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return fmt.Errorf("failed to list PVCs: %w", err)
	}

	for _, pvc := range pvcs.Items {
		for _, pattern := range patterns {
			if matchesPattern(pvc.Name, pattern) {
				_ = client.CoreV1().PersistentVolumeClaims(namespace).Delete(ctx, pvc.Name, metav1.DeleteOptions{})
				break
			}
		}
	}
	return nil
}

func DeleteNamespace(client kubernetes.Interface, ns string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	return client.CoreV1().Namespaces().Delete(ctx, ns, metav1.DeleteOptions{})
}

func DeleteClusterRolesByLabel(client kubernetes.Interface, labelSelector string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	roles, _ := client.RbacV1().ClusterRoles().List(ctx, metav1.ListOptions{LabelSelector: labelSelector})
	if roles != nil {
		for _, r := range roles.Items {
			_ = client.RbacV1().ClusterRoles().Delete(ctx, r.Name, metav1.DeleteOptions{})
		}
	}

	bindings, _ := client.RbacV1().ClusterRoleBindings().List(ctx, metav1.ListOptions{LabelSelector: labelSelector})
	if bindings != nil {
		for _, b := range bindings.Items {
			_ = client.RbacV1().ClusterRoleBindings().Delete(ctx, b.Name, metav1.DeleteOptions{})
		}
	}
	return nil
}

func GetPVCStatus(client kubernetes.Interface, namespace, labelSelector string) ([]PVCInfo, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pvcs, err := client.CoreV1().PersistentVolumeClaims(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, err
	}

	var result []PVCInfo
	for _, pvc := range pvcs.Items {
		result = append(result, PVCInfo{
			Name:     pvc.Name,
			Status:   string(pvc.Status.Phase),
			Capacity: pvc.Status.Capacity.Storage().String(),
		})
	}
	return result, nil
}

type PVCInfo struct {
	Name     string
	Status   string
	Capacity string
}

func toSchemaGVR(gvr metav1.GroupVersionResource) schema.GroupVersionResource {
	return schema.GroupVersionResource{
		Group:    gvr.Group,
		Version:  gvr.Version,
		Resource: gvr.Resource,
	}
}


func matchesPattern(name, pattern string) bool {
	// Simple prefix matching for PVC cleanup patterns like "state-", "workspace-", "obsidian-", "tailscale-"
	if len(pattern) > 0 && pattern[len(pattern)-1] == '*' {
		prefix := pattern[:len(pattern)-1]
		return len(name) >= len(prefix) && name[:len(prefix)] == prefix
	}
	return name == pattern
}
