package kube

import (
	"context"
	"fmt"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
)

var (
	gatewayGVR = schema.GroupVersionResource{
		Group: "gateway.networking.k8s.io", Version: "v1", Resource: "gateways",
	}
	httpRouteGVR = schema.GroupVersionResource{
		Group: "gateway.networking.k8s.io", Version: "v1", Resource: "httproutes",
	}
)

type Route struct {
	Name string
	Path string
}

func WaitGatewayProgrammed(ctx context.Context, dynClient dynamic.Interface, name, namespace string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		reqCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		gw, err := dynClient.Resource(gatewayGVR).Namespace(namespace).Get(reqCtx, name, metav1.GetOptions{})
		cancel()
		if err == nil {
			if isConditionTrue(gw, "Programmed") {
				return nil
			}
		}
		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("gateway %s not programmed after %s", name, timeout)
}

func IsGatewayProgrammed(dynClient dynamic.Interface, name, namespace string) (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	gw, err := dynClient.Resource(gatewayGVR).Namespace(namespace).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return false, err
	}
	return isConditionTrue(gw, "Programmed"), nil
}

func GetHTTPRoutes(dynClient dynamic.Interface, namespace, labelSelector string) ([]Route, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	list, err := dynClient.Resource(httpRouteGVR).Namespace(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list HTTPRoutes: %w", err)
	}
	var routes []Route
	for _, item := range list.Items {
		rules, _, _ := unstructured.NestedSlice(item.Object, "spec", "rules")
		for _, rule := range rules {
			if ruleMap, ok := rule.(map[string]interface{}); ok {
				matches, _, _ := unstructured.NestedSlice(ruleMap, "matches")
				for _, match := range matches {
					if matchMap, ok := match.(map[string]interface{}); ok {
						path, _, _ := unstructured.NestedString(matchMap, "path", "value")
						if path != "" {
							routes = append(routes, Route{
								Name: item.GetName(),
								Path: path,
							})
						}
					}
				}
			}
		}
	}
	return routes, nil
}

func GetEnvoyProxyService(client kubernetes.Interface, gatewayName, namespace string) (svcName string, port int32, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	label := fmt.Sprintf("gateway.envoyproxy.io/owning-gateway-name=%s", gatewayName)
	svcs, err := client.CoreV1().Services(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: label,
	})
	if err != nil {
		return "", 0, fmt.Errorf("failed to find envoy proxy service: %w", err)
	}
	if len(svcs.Items) == 0 {
		return "", 0, fmt.Errorf("no envoy proxy service found for gateway %s", gatewayName)
	}
	svc := svcs.Items[0]
	if len(svc.Spec.Ports) > 0 {
		port = svc.Spec.Ports[0].Port
	}
	return svc.Name, port, nil
}

func isConditionTrue(obj *unstructured.Unstructured, condType string) bool {
	conditions, _, _ := unstructured.NestedSlice(obj.Object, "status", "conditions")
	for _, c := range conditions {
		if cMap, ok := c.(map[string]interface{}); ok {
			t, _ := cMap["type"].(string)
			s, _ := cMap["status"].(string)
			if t == condType && s == "True" {
				return true
			}
		}
	}
	return false
}
