# CLAUDE.md - Project Context for AI Assistants

This file provides comprehensive context about the SFTPGo GKE deployment project for AI assistants (like Claude) working on this codebase.

## Project Overview

**Purpose**: Production-ready deployment solution for SFTPGo on Google Kubernetes Engine (GKE) with external PostgreSQL database, automated backups to Google Cloud Storage, and GitLab CI/CD integration.

**Target Users**: DevOps engineers and system administrators deploying SFTPGo on GCP.

**Languages**: Bilingual documentation (English and Thai).

## Key Technical Decisions

### Architecture Choices

1. **External PostgreSQL Database**
   - SFTPGo uses PostgreSQL for metadata (users, permissions, configurations)
   - Supports both Cloud SQL and self-hosted PostgreSQL
   - Connection details configured via Kubernetes secrets

2. **Storage Architecture**
   - **Application Data PVC** (100GB): SFTPGo application data and configurations
   - **User Files PVC** (500GB): SFTP user uploaded files
   - Both use GCE persistent disks with automatic labeling

3. **High Availability**
   - 2 replica deployment for redundancy
   - PodDisruptionBudget ensures minimum 1 pod available during maintenance
   - LoadBalancer services with static IP for consistent endpoints

4. **Backup Strategy**
   - Daily automated backups at 2 AM Asia/Bangkok time (19:00 UTC) via CronJob
   - Backups include: PostgreSQL dump + SFTPGo data directory + user files
   - Stored in GCS with 30-day retention (configurable)
   - Comprehensive error handling and cleanup mechanisms

5. **Region Choice**
   - **Default Region**: asia-southeast1
   - All resources (GKE, Cloud SQL, GCS, Static IPs) should be in same region for performance

### Implementation Details

#### Backup Script Architecture (`scripts/backup.sh`)
- **Trap-based cleanup**: Ensures temporary files are removed even on failure
- **Environment validation**: Pre-flight checks for all required variables
- **Command availability checks**: Verifies required tools exist before execution
- **Proper error handling**: Uses conditional execution instead of `set -e` with `$?` checks
- **Date comparison**: Uses Unix timestamps for reliable cross-platform date math
- **Structured logging**: Clear success/failure indicators with checkmarks/crosses

#### CronJob Implementation (`k8s/cronjob-backup.yaml`)
- **Alpine-based container**: Lightweight image with PostgreSQL client and gcloud SDK
- **Script mounting**: Backup script mounted as ConfigMap, copied to temp location
- **GCS authentication**: GOOGLE_APPLICATION_CREDENTIALS environment variable properly set
- **Resource limits**: CPU 250m request / 1000m limit, Memory 256Mi request / 1Gi limit
- **RBAC**: ServiceAccount with minimal required permissions (secrets read, pods list)

#### GCP Resource Labeling
All GCP resources include standardized labels:
- `app=sftpgo` - Application identifier
- `project=sftpgo-gke` - Project identifier

Applied to:
- Kubernetes resources (deployments, pods, services, etc.)
- GCE persistent disks (via volume annotations)
- Static IP addresses
- GCS buckets
- Cloud SQL instances

## File Structure and Purpose

```
sftpgo-gke/
├── .gitlab-ci.yml              # CI/CD pipeline (validate, build, deploy stages)
├── Dockerfile.backup           # Backup job container (Alpine + gcloud + psql + kubectl)
├── README.md                   # Project overview and quick start
├── CLAUDE.md                   # This file - AI assistant context
│
├── docs/
│   ├── INSTALLATION_EN.md      # Comprehensive English installation guide
│   ├── INSTALLATION_TH.md      # Comprehensive Thai installation guide
│   ├── FAQ_EN.md               # English frequently asked questions
│   ├── FAQ_TH.md               # Thai frequently asked questions
│   └── GCP_LABELS.md           # GCP resource labeling documentation
│
├── k8s/
│   ├── namespace.yaml          # Namespace: sftpgo
│   ├── configmap.yaml          # Non-sensitive config (GCS bucket, retention)
│   ├── secret.yaml             # TEMPLATE - Must be updated before deployment!
│   │                           # Contains: DB credentials, admin credentials, GCS SA key
│   ├── persistent-volume-claim.yaml  # 2 PVCs: sftpgo-data (100GB), sftpgo-user-data (500GB)
│   ├── deployment.yaml         # SFTPGo deployment (2 replicas, v2.5 image)
│   ├── service.yaml            # 3 services: sftp (LoadBalancer), web (LoadBalancer), internal (ClusterIP)
│   ├── poddisruptionbudget.yaml  # PDB ensuring minAvailable: 1 pod
│   └── cronjob-backup.yaml     # Daily backup job at 2 AM Bangkok (19:00 UTC)
│
└── scripts/
    ├── reserve-static-ip.sh    # Reserve GCP static IP with labels
    ├── backup.sh               # Production-ready backup script with comprehensive error handling
    └── restore.sh              # Restore from GCS backup (supports --db-only, --data-only)
```

## Critical Files That Need Updating Before Deployment

### 1. `k8s/secret.yaml` (CRITICAL - Contains placeholder values)

**Must update**:
- `POSTGRES_HOST` - Your PostgreSQL server IP/hostname
- `POSTGRES_PASSWORD` - Secure database password
- `SFTPGO_ADMIN_PASSWORD` - Secure admin password for web interface
- `SFTPGO_JWT_SECRET` - Random secret key for JWT tokens
- `credentials.json` - Full GCS service account JSON key

**Security note**: This file contains sensitive data and should never be committed with real credentials.

### 2. `k8s/configmap.yaml`

**Must update**:
- `GCS_BUCKET_NAME` - Your actual GCS bucket name (e.g., `gs://sftpgo-backups-your-project-id`)

### 3. `k8s/service.yaml`

**Must update**:
- `loadBalancerIP` in sftpgo-sftp service - Your reserved static IP address

## Common Tasks

### Task 1: Adding a New Kubernetes Manifest

1. Create the YAML file in `k8s/` directory
2. Add standard labels: `app: sftpgo`, `project: sftpgo-gke`
3. Update `README.md` project structure section
4. Update installation guides (both EN and TH) with deployment steps
5. Test deployment in development environment

### Task 2: Modifying Backup Script

**Location**: `scripts/backup.sh`

**Important considerations**:
- Always test changes with dry-run first
- Maintain trap-based cleanup function
- Preserve environment variable validation
- Update ConfigMap after changes: `kubectl create configmap backup-scripts --from-file=backup.sh=scripts/backup.sh --namespace=sftpgo --dry-run=client -o yaml | kubectl apply -f -`
- Test error conditions (network failure, disk full, etc.)

### Task 3: Changing Backup Schedule

**Location**: `k8s/cronjob-backup.yaml:11`

```yaml
schedule: "0 19 * * *"  # Cron format: minute hour day month weekday
```

**Current schedule**: Daily at 2 AM Asia/Bangkok time (19:00 UTC)

**Common schedules**:
- Daily at 2 AM Bangkok: `"0 19 * * *"` (19:00 UTC)
- Daily at 2 AM UTC: `"0 2 * * *"`
- Every 6 hours: `"0 */6 * * *"`
- Weekly on Sunday at 3 AM Bangkok: `"0 20 * * 0"` (20:00 UTC on Saturday)

### Task 4: Updating Documentation

**Both languages required**: Always update both `INSTALLATION_EN.md` and `INSTALLATION_TH.md` with parallel changes.

**Format**:
- Use clear step numbers
- Include verification commands
- Add expected output examples
- Update table of contents if adding new sections

### Task 5: Changing Region

**Files to update**:
1. `.gitlab-ci.yml` - Update `GCP_REGION` variable default
2. `scripts/reserve-static-ip.sh` - Update default region in script
3. `docs/INSTALLATION_EN.md` - Update all region examples
4. `docs/INSTALLATION_TH.md` - Update all region examples
5. `docs/FAQ_EN.md` - Update region-specific answers
6. `docs/FAQ_TH.md` - Update region-specific answers

**Important**: All resources must be in same region (GKE, Cloud SQL, GCS, Static IP).

## Production Readiness Checklist

✅ **Completed and Production Ready**:
- [x] Critical bug fixes (backup script, GCS auth, error handling)
- [x] Environment variable validation
- [x] Cleanup on failure (trap functions)
- [x] Consistent GCP labeling
- [x] PodDisruptionBudget for HA
- [x] Resource limits on all workloads
- [x] Command availability checks
- [x] Proper date handling in backup retention
- [x] Comprehensive documentation (EN/TH)

⚠️ **Still Using Placeholder Values**:
- [ ] Update `k8s/secret.yaml` with real credentials
- [ ] Reserve static IP and update `k8s/service.yaml`
- [ ] Create GCS bucket and update `k8s/configmap.yaml`

🔄 **Recommended Future Enhancements** (not blocking):
- [ ] Add Prometheus metrics and Grafana dashboards
- [ ] Implement TLS/SSL for web interface (cert-manager)
- [ ] Add network policies for pod-to-pod communication
- [ ] Implement backup encryption at rest
- [ ] Add health check endpoints to backup jobs
- [ ] Create Helm chart for easier deployment
- [ ] Add automated restore testing

## Git Workflow

**Branch**: `claude/sftpgo-gke-deployment-011CUxJhYqBofsUXd3GaAput`

**Commit Message Format**:
```
Brief summary (imperative mood)

CATEGORY:
- Item 1
- Item 2

FILES MODIFIED/ADDED/REMOVED:
- path/to/file - Description of change
```

**Push Requirements**:
- Always use: `git push -u origin <branch-name>`
- Branch must start with `claude/` and end with session ID
- Retry up to 4 times with exponential backoff on network failures

## Important Patterns and Standards

### 1. Bash Script Standards
```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Cleanup trap
cleanup() {
    # Cleanup logic
}
trap cleanup EXIT ERR INT TERM

# Environment validation
required_vars=("VAR1:Description" "VAR2:Description")
for var_info in "${required_vars[@]}"; do
    var_name="${var_info%%:*}"
    if [ -z "${!var_name}" ]; then
        echo "✗ Error: ${var_info##*:} not set"
        exit 1
    fi
done

# Command availability
required_commands=("cmd1" "cmd2")
for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "✗ Error: Required command '$cmd' not found"
        exit 1
    fi
done
```

### 2. Kubernetes Resource Labels
```yaml
metadata:
  labels:
    app: sftpgo           # Always consistent
    project: sftpgo-gke   # Always consistent
```

### 3. GCP Resource Labels
```bash
gcloud <service> create <name> \
  --labels=app=sftpgo,project=sftpgo-gke \
  # ... other flags
```

## Known Constraints and Limitations

1. **SFTPGo Version**: Currently pinned to v2.5.x
   - Rationale: Stable release with tested PostgreSQL support
   - Upgrade consideration: Test thoroughly in dev before updating image tag

2. **Static IP Requirement**: Cannot use ephemeral IPs
   - Reason: SFTP clients need consistent endpoint for firewall rules
   - Cost: Static IPs incur small charge (~$0.01/hour in asia-southeast1)

3. **PostgreSQL External Only**: No in-cluster PostgreSQL option provided
   - Rationale: Production deployments should use managed database (Cloud SQL)
   - If needed: User can add PostgreSQL deployment themselves

4. **Single Namespace**: All resources in `sftpgo` namespace
   - Rationale: Simplifies resource management and RBAC
   - Multi-tenancy: Not supported in current design

5. **Backup Window**: Currently set to 2 AM Asia/Bangkok time (19:00 UTC)
   - Users can modify CronJob schedule in `k8s/cronjob-backup.yaml` if different time needed

## Security Considerations

1. **Secrets Management**
   - Never commit real secrets to git
   - Consider using external secret management (Google Secret Manager, Vault)
   - Rotate credentials regularly

2. **Service Account Permissions**
   - Backup SA has Storage Admin (broad permissions)
   - Consider restricting to specific bucket using IAM conditions

3. **Network Security**
   - Currently no NetworkPolicies defined
   - LoadBalancer services are publicly accessible
   - Consider adding Cloud Armor for DDoS protection

4. **Pod Security**
   - No PodSecurityPolicy or PodSecurityStandards defined
   - Containers run as root by default
   - Consider adding security contexts with non-root users

## Troubleshooting Guide

### Issue: Backup Job Fails

**Check**:
1. CronJob logs: `kubectl logs -n sftpgo job/<job-name>`
2. GCS credentials: `kubectl get secret sftpgo-secrets -n sftpgo -o yaml | grep credentials.json`
3. PostgreSQL connectivity: `kubectl exec -it -n sftpgo <pod-name> -- nc -zv $POSTGRES_HOST 5432`

**Common causes**:
- Missing GOOGLE_APPLICATION_CREDENTIALS env var ✅ FIXED
- Incorrect GCS credentials
- Network connectivity to PostgreSQL
- Insufficient permissions on GCS bucket

### Issue: Pods Not Starting

**Check**:
1. Pod status: `kubectl describe pod -n sftpgo <pod-name>`
2. PVC status: `kubectl get pvc -n sftpgo`
3. Events: `kubectl get events -n sftpgo --sort-by='.lastTimestamp'`

**Common causes**:
- PVC not bound (check storage class exists)
- Image pull errors (check image name and registry access)
- Secrets not found (check secrets exist in namespace)
- Resource quota exceeded

### Issue: External IP Not Assigned

**Check**:
1. Service status: `kubectl describe service sftpgo-sftp -n sftpgo`
2. Static IP exists: `gcloud compute addresses list --filter="name=sftpgo-static-ip"`
3. Static IP not in use: Check no other service using the IP

**Common causes**:
- Static IP in wrong region
- Static IP already assigned to another resource
- Load balancer quota exceeded

## Environment Variables Reference

### Required for Backup Script
```bash
POSTGRES_HOST           # PostgreSQL hostname/IP
POSTGRES_PORT           # PostgreSQL port (default: 5432)
POSTGRES_DB             # Database name (default: sftpgo)
POSTGRES_USER           # Database user
POSTGRES_PASSWORD       # Database password
GCS_BUCKET              # Full GCS bucket path (gs://bucket-name)
RETENTION_DAYS          # Backup retention days (default: 30)
NAMESPACE               # Kubernetes namespace (default: sftpgo)
GOOGLE_APPLICATION_CREDENTIALS  # Path to GCS SA key JSON
```

### GitLab CI/CD Variables
```bash
GCP_PROJECT_ID          # GCP project ID
GCP_REGION              # GCP region (e.g., asia-southeast1)
GKE_CLUSTER_NAME        # GKE cluster name
GKE_ZONE                # GKE zone (e.g., asia-southeast1-a)
GCP_SERVICE_KEY         # Base64 encoded service account key
```

## Testing Recommendations

### Before Deploying Changes

1. **Manifest Validation**
   ```bash
   kubectl apply --dry-run=client -f k8s/
   ```

2. **Script Validation**
   ```bash
   shellcheck scripts/*.sh
   bash -n scripts/*.sh  # Syntax check
   ```

3. **Backup Script Test** (in test environment)
   ```bash
   # Set test environment variables
   export POSTGRES_HOST=test-db
   export GCS_BUCKET=gs://test-bucket
   # ... other vars

   # Run with error simulation
   ./scripts/backup.sh
   ```

4. **Restore Test** (critical!)
   ```bash
   # In test environment, restore latest backup
   ./scripts/restore.sh gs://bucket/backups/2024-01-15/backup.tar.gz

   # Verify data integrity
   # Check SFTPGo web interface
   # Test SFTP connection
   ```

## Useful Commands Quick Reference

```bash
# View all resources in namespace
kubectl get all -n sftpgo

# View pod logs (follow mode)
kubectl logs -n sftpgo -l app=sftpgo -f --tail=100

# Execute command in pod
kubectl exec -it -n sftpgo <pod-name> -- /bin/sh

# Port forward to web interface (local testing)
kubectl port-forward -n sftpgo svc/sftpgo-internal 8080:8080

# Manually trigger backup job
kubectl create job -n sftpgo --from=cronjob/sftpgo-backup manual-backup-$(date +%s)

# View recent events
kubectl get events -n sftpgo --sort-by='.lastTimestamp' | tail -20

# Check PVC disk usage
kubectl exec -n sftpgo <pod-name> -- df -h /srv/sftpgo /srv/sftpgo/data

# View secret values (base64 decoded)
kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_HOST}' | base64 -d

# List backups in GCS
gsutil ls -lh gs://sftpgo-backups-project-id/backups/
```

## Contact and Support

- **SFTPGo Documentation**: https://github.com/drakkan/sftpgo/blob/main/docs/README.md
- **GKE Documentation**: https://cloud.google.com/kubernetes-engine/docs
- **Project Issues**: Check FAQ_EN.md and FAQ_TH.md first

---

**Last Updated**: 2024-11-09
**Version**: 1.0.0
**Status**: Production Ready (with placeholder secrets)
