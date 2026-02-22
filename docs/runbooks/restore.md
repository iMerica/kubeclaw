# Runbook: Restore an OpenClaw Gateway from Backup

## Overview

This runbook covers restoring an OpenClaw Gateway from a CSI `VolumeSnapshot` or a manual PVC backup. The Gateway stores all state — config, auth tokens, sessions, channel state, and workspace — under `/home/node/.openclaw`.

**What needs to be backed up:**
- Primary PVC: `/home/node/.openclaw` (excluding workspace if split)
- Workspace PVC: `/home/node/.openclaw/workspace` (if split volumes enabled)

---

## Prerequisites

For CSI snapshot restore:
- CSI snapshot controller installed in cluster
- `VolumeSnapshot` and `VolumeSnapshotClass` CRDs present
- Snapshot exists (created manually or via automation)

For manual restore:
- A backup archive (tarball) of the state directory contents
- `kubectl` access to the target namespace

---

## Method 1: CSI VolumeSnapshot Restore

### Step 1: Identify the snapshot to restore

```sh
kubectl -n <tenant-namespace> get volumesnapshots
# Example output:
# NAME                              READYTOUSE   SOURCEPVC             SNAPSHOTCONTENT   AGE
# openclaw-tenant-a-20240115103000  true         state-openclaw-gateway-0  ...           2h
```

### Step 2: Scale down the Gateway

The Gateway must not be running during restore to avoid data corruption.

```sh
kubectl -n <tenant-namespace> scale statefulset/openclaw-gateway --replicas=0
# Wait for pod termination:
kubectl -n <tenant-namespace> wait pod -l app.kubernetes.io/name=openclaw \
  --for=delete --timeout=120s
```

### Step 3: Delete the existing PVC

**WARNING**: This is destructive. Verify the snapshot is `READYTOUSE: true` before proceeding.

```sh
kubectl -n <tenant-namespace> delete pvc state-openclaw-gateway-0
```

### Step 4: Restore PVC from snapshot

Create a new PVC from the snapshot. The name must match exactly what the StatefulSet expects.

```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: state-openclaw-gateway-0
  namespace: <tenant-namespace>
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: <your-storage-class>
  resources:
    requests:
      storage: <size-matching-original>
  dataSource:
    name: openclaw-tenant-a-20240115103000  # snapshot name from Step 1
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF
```

Wait for the PVC to be bound:

```sh
kubectl -n <tenant-namespace> wait pvc/state-openclaw-gateway-0 \
  --for=jsonpath='{.status.phase}'=Bound --timeout=300s
```

### Step 5: Scale the Gateway back up

```sh
kubectl -n <tenant-namespace> scale statefulset/openclaw-gateway --replicas=1
kubectl -n <tenant-namespace> rollout status statefulset/openclaw-gateway
```

### Step 6: Verify health

```sh
kubectl -n <tenant-namespace> exec statefulset/openclaw-gateway -- \
  node dist/index.js health
kubectl -n <tenant-namespace> exec statefulset/openclaw-gateway -- \
  node dist/index.js status
kubectl -n <tenant-namespace> exec statefulset/openclaw-gateway -- \
  node dist/index.js doctor
```

---

## Method 2: Manual Backup / Restore

### Backup: Create a tarball from the running Gateway

```sh
# Create a backup directory on your local machine:
mkdir -p ./openclaw-backup

# Export state directory (pod must be running):
kubectl -n <namespace> exec statefulset/<release-name> -- \
  tar czf - /home/node/.openclaw \
  > ./openclaw-backup/openclaw-state-$(date +%Y%m%d%H%M%S).tar.gz

echo "Backup created: $(ls -lh ./openclaw-backup/*.tar.gz)"
```

> **Workspace note**: If split volumes are enabled, also back up:
> ```sh
> kubectl -n <namespace> exec statefulset/<release-name> -- \
>   tar czf - /home/node/.openclaw/workspace \
>   > ./openclaw-backup/openclaw-workspace-$(date +%Y%m%d%H%M%S).tar.gz
> ```

### Restore: Copy backup to a new or existing PVC

#### Step 1: Scale down Gateway

```sh
kubectl -n <namespace> scale statefulset/<release-name> --replicas=0
kubectl -n <namespace> wait pod -l app.kubernetes.io/instance=<release-name> \
  --for=delete --timeout=120s
```

#### Step 2: Run a temporary restore pod

```sh
kubectl -n <namespace> run restore-helper \
  --image=busybox \
  --restart=Never \
  --overrides='{
    "spec": {
      "volumes": [{
        "name": "state",
        "persistentVolumeClaim": {"claimName": "<pvc-name>"}
      }],
      "containers": [{
        "name": "restore-helper",
        "image": "busybox",
        "command": ["sleep", "3600"],
        "volumeMounts": [{"name": "state", "mountPath": "/data"}]
      }]
    }
  }' \
  -- sleep 3600
kubectl -n <namespace> wait pod/restore-helper --for=condition=Ready --timeout=60s
```

#### Step 3: Copy backup into the PVC

```sh
kubectl -n <namespace> cp \
  ./openclaw-backup/openclaw-state-20240115103000.tar.gz \
  restore-helper:/tmp/backup.tar.gz

kubectl -n <namespace> exec restore-helper -- sh -c \
  "cd /data && tar xzf /tmp/backup.tar.gz --strip-components=3"
# --strip-components=3 removes "home/node/.openclaw" prefix,
# leaving files directly under /data

# Verify:
kubectl -n <namespace> exec restore-helper -- ls -la /data/
```

#### Step 4: Clean up restore pod

```sh
kubectl -n <namespace> delete pod restore-helper
```

#### Step 5: Start Gateway and verify

```sh
kubectl -n <namespace> scale statefulset/<release-name> --replicas=1
kubectl -n <namespace> rollout status statefulset/<release-name>

kubectl -n <namespace> exec statefulset/<release-name> -- \
  node dist/index.js doctor
kubectl -n <namespace> exec statefulset/<release-name> -- \
  node dist/index.js status
```

---

## Post-Restore Checklist

- [ ] Gateway pods are Running and Ready (readiness probe passes)
- [ ] `openclaw doctor` reports no critical issues
- [ ] `openclaw status` shows expected gateway state
- [ ] `openclaw channels status --probe` shows connected channels (if applicable)
- [ ] Control UI is accessible and authenticated
- [ ] No unexpected PVC size changes (check `kubectl get pvc`)
- [ ] Verify no stale snapshot residue (clean up old snapshots if retainCount exceeded)

---

## Snapshot Retention

If using automated snapshots, enforce retention by cleaning up old snapshots:

```sh
# List all snapshots for a tenant, sorted by age:
kubectl -n <tenant-namespace> get volumesnapshots \
  -l openclaw.dev/tenant=<tenant-name> \
  --sort-by=.metadata.creationTimestamp

# Delete oldest (example: keep 3, delete the rest):
kubectl -n <tenant-namespace> get volumesnapshots \
  -l openclaw.dev/tenant=<tenant-name> \
  --sort-by=.metadata.creationTimestamp \
  -o name \
  | head -n -3 \
  | xargs kubectl -n <tenant-namespace> delete
```

---

## Troubleshooting

### Gateway fails to start after restore

Run doctor to repair config issues:
```sh
kubectl -n <namespace> exec statefulset/<release-name> -- \
  node dist/index.js doctor --yes
```

### Config is invalid after restore

If the config file is corrupted, overwrite with desired config:
```sh
kubectl -n <namespace> exec statefulset/<release-name> -- \
  node dist/index.js config apply <path-to-valid-config>
```

Or delete the config file and let the Gateway regenerate defaults:
```sh
kubectl -n <namespace> exec statefulset/<release-name> -- \
  rm /home/node/.openclaw/openclaw.json
kubectl -n <namespace> rollout restart statefulset/<release-name>
```

### PVC not binding after snapshot restore

Check the `VolumeSnapshotContent` status and storage class availability:
```sh
kubectl describe volumesnapshot -n <namespace> <snapshot-name>
kubectl get volumesnapshotcontent
kubectl get storageclass
```
