# Runbook: Restore an OpenClaw Gateway from Backup

## Overview

This runbook covers restoring an OpenClaw Gateway from a CSI `VolumeSnapshot`, a manual PVC backup, or an S3 backup (created by the chart's `backup.enabled` feature). The Gateway stores all state as plain Markdown files under `/home/node/.openclaw`.

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

## Method 3: Restore from S3 Backup

If the chart's S3 backup feature (`backup.enabled: true`) is configured, scheduled and pre-delete backups are stored in your S3-compatible bucket. This method uses rclone to pull the backup into the PVC.

### Step 1: Identify the backup to restore

List available backups in your S3 bucket:

```sh
# Using rclone (configure S3 remote first, or use env-based config):
export RCLONE_CONFIG_S3_TYPE=s3
export RCLONE_CONFIG_S3_PROVIDER=Other
export RCLONE_CONFIG_S3_ENDPOINT="https://s3.us-east-1.amazonaws.com"
export RCLONE_CONFIG_S3_ACCESS_KEY_ID="AKIA..."
export RCLONE_CONFIG_S3_SECRET_ACCESS_KEY="..."

rclone lsd s3:<bucket>/<namespace>/<release>/
# Example output:
#           -1 2026-03-07T02-00-00Z
#           -1 2026-03-08T02-00-00Z
#           -1 pre-delete
```

The `pre-delete/` directory contains the most recent pre-uninstall snapshot. Timestamped directories are from scheduled backups.

### Step 2: Scale down the Gateway

```sh
kubectl -n <namespace> scale statefulset/<release-name>-gateway --replicas=0
kubectl -n <namespace> wait pod -l app.kubernetes.io/instance=<release-name> \
  --for=delete --timeout=120s
```

### Step 3: Run a temporary restore pod with rclone

```sh
kubectl -n <namespace> run restore-from-s3 \
  --image=rclone/rclone:1.68 \
  --restart=Never \
  --env="S3_ENDPOINT=https://s3.us-east-1.amazonaws.com" \
  --env="S3_BUCKET=<bucket>" \
  --env="S3_ACCESS_KEY_ID=AKIA..." \
  --env="S3_SECRET_ACCESS_KEY=..." \
  --overrides='{
    "spec": {
      "volumes": [{
        "name": "state",
        "persistentVolumeClaim": {"claimName": "<state-pvc-name>"}
      }],
      "containers": [{
        "name": "restore-from-s3",
        "image": "rclone/rclone:1.68",
        "command": ["sleep", "3600"],
        "volumeMounts": [{"name": "state", "mountPath": "/data"}]
      }]
    }
  }' \
  -- sleep 3600

kubectl -n <namespace> wait pod/restore-from-s3 --for=condition=Ready --timeout=60s
```

### Step 4: Pull the backup into the PVC

```sh
# Choose which backup to restore (timestamp or "pre-delete"):
BACKUP="2026-03-08T02-00-00Z"

kubectl -n <namespace> exec restore-from-s3 -- sh -c "
  export RCLONE_CONFIG_S3_TYPE=s3
  export RCLONE_CONFIG_S3_PROVIDER=Other
  export RCLONE_CONFIG_S3_ENDPOINT=\"\${S3_ENDPOINT}\"
  export RCLONE_CONFIG_S3_ACCESS_KEY_ID=\"\${S3_ACCESS_KEY_ID}\"
  export RCLONE_CONFIG_S3_SECRET_ACCESS_KEY=\"\${S3_SECRET_ACCESS_KEY}\"
  rclone copy s3:\${S3_BUCKET}/<namespace>/<release>/${BACKUP} /data \
    --transfers 8 --s3-no-check-bucket --log-level INFO
"

# Verify:
kubectl -n <namespace> exec restore-from-s3 -- ls -la /data/
```

### Step 5: Clean up and restart

```sh
kubectl -n <namespace> delete pod restore-from-s3
kubectl -n <namespace> scale statefulset/<release-name>-gateway --replicas=1
kubectl -n <namespace> rollout status statefulset/<release-name>-gateway
```

### Step 6: Verify health

```sh
kubectl -n <namespace> exec statefulset/<release-name>-gateway -- \
  node dist/index.js doctor
kubectl -n <namespace> exec statefulset/<release-name>-gateway -- \
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
# List all snapshots in the namespace, sorted by age:
kubectl -n <namespace> get volumesnapshots \
  -l app.kubernetes.io/instance=<release-name> \
  --sort-by=.metadata.creationTimestamp

# Delete oldest (example: keep 3, delete the rest):
kubectl -n <namespace> get volumesnapshots \
  -l app.kubernetes.io/instance=<release-name> \
  --sort-by=.metadata.creationTimestamp \
  -o name \
  | head -n -3 \
  | xargs kubectl -n <namespace> delete
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
