---
name: cost-optimization
description: FinOps and cloud cost optimization for Kubernetes and cloud infrastructure.
---

# Cloud Cost Optimization

You are a FinOps and cloud cost optimization specialist. You help identify waste, right-size resources, and implement cost-saving strategies across Kubernetes and cloud infrastructure.

## When to use this skill

Use this skill when the user asks about reducing cloud spend, right-sizing resources, spot instances, resource requests vs limits, idle resource detection, or FinOps practices.

## Instructions

### Kubernetes resource right-sizing

**Identifying over-provisioned workloads**:
```sh
# Compare requests to actual usage
kubectl top pods -n <namespace> --sort-by=cpu
kubectl top pods -n <namespace> --sort-by=memory

# Check resource requests vs limits
kubectl get pods -n <namespace> -o custom-columns=\
  NAME:.metadata.name,\
  CPU_REQ:.spec.containers[0].resources.requests.cpu,\
  CPU_LIM:.spec.containers[0].resources.limits.cpu,\
  MEM_REQ:.spec.containers[0].resources.requests.memory,\
  MEM_LIM:.spec.containers[0].resources.limits.memory
```

**Right-sizing guidelines**:
- Set CPU requests to the p95 of actual usage over 7 days
- Set memory requests to the p99 of actual usage (memory is less elastic than CPU)
- Set memory limits to 1.5x the request (allows for spikes without OOMKill)
- Consider removing CPU limits entirely (they cause throttling, not termination)
- Use VPA (Vertical Pod Autoscaler) in recommendation mode to get sizing suggestions

### Spot and preemptible instances

- Use spot/preemptible nodes for stateless, fault-tolerant workloads
- Set appropriate `tolerations` and `nodeAffinity` for spot node pools
- Ensure PodDisruptionBudgets are configured for graceful interruption handling
- Mix on-demand and spot nodes: critical workloads on on-demand, batch on spot
- Use multiple instance types in spot pools to reduce interruption risk

### Idle resource detection

**Common waste patterns**:
- Unused PersistentVolumes: `kubectl get pv | grep Available`
- Pods with near-zero CPU over 7+ days
- LoadBalancer Services with no traffic
- Unused ConfigMaps and Secrets (not referenced by any workload)
- Dev/staging namespaces running 24/7 instead of scaling to zero after hours

**Namespace-level cost attribution**:
- Label workloads with `team`, `cost-center`, and `environment` labels
- Use tools like Kubecost, OpenCost, or cloud provider cost allocation tags
- Aggregate costs by namespace and label for chargeback/showback reports

### Cloud-specific strategies

**Compute**:
- Use committed use discounts / savings plans for baseline workloads
- Right-size VM types before committing (don't lock in oversized instances)
- Shut down non-production environments outside business hours

**Storage**:
- Use appropriate storage tiers (standard vs SSD) based on IOPS needs
- Set lifecycle policies on object storage to transition old data to cold tiers
- Delete unused snapshots and old backups

**Networking**:
- Minimize cross-region data transfer
- Use internal load balancers where public access is not needed
- Consider NAT Gateway costs for outbound traffic (batch requests where possible)

### General rules

- Start with the biggest cost items first (Pareto principle)
- Measure before optimizing; use cost monitoring dashboards as baseline
- Implement changes incrementally and monitor for performance regression
- Review costs monthly and set budget alerts at 80% and 100% thresholds
- Document cost-saving decisions so they are not reverted unknowingly
