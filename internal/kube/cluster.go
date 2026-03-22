package kube

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

func CheckCluster(client kubernetes.Interface) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_, err := client.Discovery().ServerVersion()
	_ = ctx
	if err != nil {
		return fmt.Errorf("cannot reach cluster: %w", err)
	}
	return nil
}

func GetStorageClasses(client kubernetes.Interface) (classes []string, defaultClass string, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	scList, err := client.StorageV1().StorageClasses().List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, "", fmt.Errorf("failed to list storage classes: %w", err)
	}
	for _, sc := range scList.Items {
		classes = append(classes, sc.Name)
		if sc.Annotations["storageclass.kubernetes.io/is-default-class"] == "true" {
			defaultClass = sc.Name
		}
	}
	return classes, defaultClass, nil
}

func EnsureNamespace(client kubernetes.Interface, ns string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_, err := client.CoreV1().Namespaces().Get(ctx, ns, metav1.GetOptions{})
	if err == nil {
		return nil
	}
	nsObj := &corev1.Namespace{
		ObjectMeta: metav1.ObjectMeta{Name: ns},
	}
	_, err = client.CoreV1().Namespaces().Create(ctx, nsObj, metav1.CreateOptions{})
	if err != nil {
		return fmt.Errorf("failed to create namespace %q: %w", ns, err)
	}
	return nil
}
