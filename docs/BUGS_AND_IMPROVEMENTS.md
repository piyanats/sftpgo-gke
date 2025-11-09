# Code Review: Bugs and Improvements

**Review Date**: 2024-11-09
**Reviewed By**: Code Review Agent
**Status**: Complete

---

## 🐛 Critical Bugs

### 1. CronJob Backup Script Injection Failure
**File**: `k8s/cronjob-backup.yaml:38`
**Severity**: 🔴 Critical
**Issue**: Command substitution in YAML heredoc will fail
```yaml
cat > /tmp/backup.sh << 'BACKUP_SCRIPT_EOF'
$(cat /backup/backup.sh)  # ❌ This won't work as intended
BACKUP_SCRIPT_EOF
```

**Impact**: Backup CronJob will not execute the actual backup script, only creating a placeholder file.

**Fix**: Change approach to directly copy the script:
```yaml
- /bin/bash
- -c
- |
  set -e
  apk add --no-cache postgresql-client
  cp /backup/backup.sh /tmp/backup.sh
  chmod +x /tmp/backup.sh
  /tmp/backup.sh
```

### 2. Missing GOOGLE_APPLICATION_CREDENTIALS
**File**: `k8s/cronjob-backup.yaml`
**Severity**: 🔴 Critical
**Issue**: GCS credentials are mounted but environment variable not set

**Impact**: Backup script cannot authenticate to GCS, all backups will fail.

**Fix**: Add environment variable:
```yaml
- name: GOOGLE_APPLICATION_CREDENTIALS
  value: /secrets/gcs/credentials.json
```

### 3. Backup Script Error Handling Issue
**File**: `scripts/backup.sh:48`
**Severity**: 🟡 High
**Issue**: Using `if [ $? -eq 0 ]` after command with `set -e` is redundant and can mask errors

```bash
pg_dump ... -f "${BACKUP_DIR}/db/sftpgo-db-${TIMESTAMP}.dump"

if [ $? -eq 0 ]; then  # ❌ Script would already exit if pg_dump failed
    echo "✓ Database backup completed"
```

**Fix**: Remove redundant check or use proper error trapping:
```bash
if pg_dump ... -f "${BACKUP_DIR}/db/sftpgo-db-${TIMESTAMP}.dump"; then
    echo "✓ Database backup completed"
else
    echo "✗ Database backup failed!"
    exit 1
fi
```

---

## ⚠️ High Priority Issues

### 4. Missing Environment Variable Validation
**File**: `scripts/backup.sh`
**Severity**: 🟡 High
**Issue**: Script doesn't validate required environment variables before use

**Impact**: Script will fail with unclear errors if variables are not set.

**Fix**: Add validation at the start:
```bash
# Validate required environment variables
required_vars=("POSTGRES_HOST" "POSTGRES_USER" "POSTGRES_PASSWORD" "GCS_BUCKET")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done
```

### 5. No Cleanup on Script Failure
**File**: `scripts/backup.sh`, `scripts/restore.sh`
**Severity**: 🟡 High
**Issue**: Temporary files are not cleaned up if script fails mid-execution

**Fix**: Add trap for cleanup:
```bash
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "${BACKUP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT ERR
```

### 6. Inconsistent GCP Label Application
**Files**: Multiple Kubernetes manifests
**Severity**: 🟡 High
**Issue**: Some resources missing `project: sftpgo-gke` label

**Missing labels in**:
- `k8s/deployment.yaml` - Deployment metadata
- `k8s/deployment.yaml` - Pod template labels
- `k8s/deployment.yaml` - ServiceAccount
- `k8s/namespace.yaml` - Namespace
- `k8s/configmap.yaml` - ConfigMap (no labels at all)
- `k8s/cronjob-backup.yaml` - All resources

**Fix**: Add labels consistently:
```yaml
metadata:
  labels:
    app: sftpgo
    project: sftpgo-gke
```

---

## 📝 Medium Priority Issues

### 7. Hardcoded Docker Image Version
**File**: `k8s/deployment.yaml:30`
**Severity**: 🟠 Medium
**Issue**: Image version hardcoded to `v2.5`

```yaml
image: drakkan/sftpgo:v2.5  # ❌ Hardcoded version
```

**Impact**: Manual updates required, no version control

**Recommendation**: Use variable or latest tag with digest pinning:
```yaml
image: drakkan/sftpgo:latest@sha256:abc123...  # Pinned digest
# Or use environment variable
image: ${SFTPGO_IMAGE:-drakkan/sftpgo:v2.5}
```

### 8. No Pod Disruption Budget
**File**: Missing `k8s/pdb.yaml`
**Severity**: 🟠 Medium
**Issue**: No PodDisruptionBudget defined for high availability deployment

**Impact**: During cluster maintenance, both pods could be evicted simultaneously, causing downtime.

**Recommendation**: Add PodDisruptionBudget:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: sftpgo-pdb
  namespace: sftpgo
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: sftpgo
```

### 9. No Resource Limits for Backup Job
**File**: `k8s/cronjob-backup.yaml`
**Severity**: 🟠 Medium
**Issue**: Backup container has no resource requests/limits

**Impact**: Backup jobs could consume excessive resources or be OOMKilled.

**Recommendation**: Add resource limits:
```yaml
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

### 10. kubectl/gcloud Command Availability Not Checked
**Files**: `scripts/backup.sh`, `scripts/restore.sh`
**Severity**: 🟠 Medium
**Issue**: Scripts don't verify required commands are available

**Recommendation**: Add command check:
```bash
for cmd in kubectl pg_dump gsutil; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: Required command '$cmd' not found"
        exit 1
    fi
done
```

### 11. Backup Retention Date Comparison
**File**: `scripts/backup.sh:113-122`
**Severity**: 🟠 Medium
**Issue**: Date comparison `[[ "${backup_date}" < "${CUTOFF_DATE}" ]]` uses string comparison

**Impact**: May not work correctly for date comparison on all systems.

**Recommendation**: Use date arithmetic:
```bash
backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || echo "0")
cutoff_timestamp=$(date -d "$CUTOFF_DATE" +%s)
if [ "$backup_timestamp" -lt "$cutoff_timestamp" ]; then
    # Delete backup
fi
```

---

## 🔍 Low Priority Issues / Improvements

### 12. Secret.yaml Contains Placeholder Credentials
**File**: `k8s/secret.yaml`
**Severity**: 🟢 Low (Documentation issue)
**Issue**: Template secret file contains placeholder credentials that must be changed

**Recommendation**:
- Add clear warning in README
- Consider adding validation script to check for default passwords
- Add to deployment checklist

### 13. GCS Bucket Name Format Unclear
**File**: `k8s/configmap.yaml:33`
**Issue**: Unclear if GCS_BUCKET_NAME should include "gs://" prefix

```yaml
GCS_BUCKET_NAME: "sftpgo-backups"  # Should this be gs://sftpgo-backups ?
```

**Recommendation**: Standardize and document:
```yaml
GCS_BUCKET_NAME: "gs://sftpgo-backups"  # Full GCS path
```

### 14. No Network Policies
**File**: Missing `k8s/network-policy.yaml`
**Severity**: 🟢 Low
**Issue**: No NetworkPolicy defined for security isolation

**Recommendation**: Add NetworkPolicy to restrict pod communication:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: sftpgo-network-policy
  namespace: sftpgo
spec:
  podSelector:
    matchLabels:
      app: sftpgo
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 2022
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - namespaceSelector: {}
  - to:  # Allow PostgreSQL
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 5432
```

### 15. No Horizontal Pod Autoscaler
**File**: Missing `k8s/hpa.yaml`
**Severity**: 🟢 Low
**Issue**: Static replica count, no auto-scaling

**Recommendation**: Add HPA for production workloads (mentioned in FAQ but not implemented)

### 16. Service Annotations May Not Work
**File**: `k8s/service.yaml:12-13`
**Issue**: Backend config annotation references non-existent resource

```yaml
cloud.google.com/backend-config: '{"default": "sftpgo-backend-config"}'
```

**Impact**: Warning in logs, annotation ignored (not critical)

**Recommendation**: Either create the BackendConfig resource or remove the annotation.

### 17. Missing Startup Probe
**File**: `k8s/deployment.yaml`
**Severity**: 🟢 Low
**Issue**: Only liveness and readiness probes defined, no startup probe for slow-starting container

**Recommendation**: Add startup probe:
```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30
  periodSeconds: 10
```

### 18. FTP Passive Mode Port Range Not Configured
**File**: `k8s/configmap.yaml`
**Severity**: 🟢 Low
**Issue**: FTP service enabled but passive port range not configured

**Impact**: FTP passive mode connections may fail

**Recommendation**: Add passive port configuration:
```yaml
SFTPGO_FTPD__BINDINGS__0__FORCE_PASSIVE_IP: "<EXTERNAL_IP>"
SFTPGO_FTPD__PASSIVE_PORT_RANGE__START: "50000"
SFTPGO_FTPD__PASSIVE_PORT_RANGE__END: "50100"
```

---

## 💡 Suggested Enhancements

### 19. Add Monitoring and Alerting
**Recommendation**: Add Prometheus ServiceMonitor
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sftpgo
  namespace: sftpgo
spec:
  selector:
    matchLabels:
      app: sftpgo
  endpoints:
  - port: http
    path: /metrics
```

### 20. Add Backup Verification Job
**Recommendation**: Create a separate CronJob to periodically verify backups can be restored

### 21. Implement GitOps with ArgoCD/Flux
**Recommendation**: Add ArgoCD Application manifest for GitOps deployment

### 22. Add cert-manager for TLS
**Recommendation**: Integrate cert-manager for automatic TLS certificate management

### 23. Add Grafana Dashboard
**Recommendation**: Create Grafana dashboard for SFTPGo metrics

### 24. Implement Secrets Management
**Recommendation**: Use External Secrets Operator or GCP Secret Manager integration instead of Kubernetes Secrets

---

## 📊 Summary

| Severity | Count | Description |
|----------|-------|-------------|
| 🔴 Critical | 3 | Must fix before production |
| 🟡 High | 3 | Should fix soon |
| 🟠 Medium | 6 | Plan to fix |
| 🟢 Low | 8 | Nice to have |
| 💡 Enhancement | 6 | Future improvements |

### Priority Action Items

1. **Fix CronJob backup script injection** (Critical)
2. **Add GOOGLE_APPLICATION_CREDENTIALS** (Critical)
3. **Fix backup script error handling** (Critical)
4. **Add environment variable validation** (High)
5. **Add cleanup traps to scripts** (High)
6. **Standardize GCP labels across all resources** (High)
7. **Add PodDisruptionBudget** (Medium)
8. **Add resource limits to backup job** (Medium)

---

## 🔧 Quick Fix Commands

Apply these fixes incrementally and test each change:

```bash
# 1. Update labels
grep -r "app: sftpgo" k8s/ | grep -v "project: sftpgo-gke"

# 2. Validate all manifests
kubectl apply --dry-run=client -f k8s/

# 3. Test backup script locally
./scripts/backup.sh --dry-run

# 4. Check for hardcoded credentials
grep -r "changeme" k8s/
```

---

## 📖 Documentation Updates Needed

1. Add security checklist before deployment
2. Document the backup restoration testing procedure
3. Add troubleshooting section for common backup failures
4. Create runbook for disaster recovery
5. Document the GCS bucket naming convention

---

**End of Review**
