# SFTPGo on GKE - Frequently Asked Questions (FAQ)

## Table of Contents

- [General Questions](#general-questions)
- [Installation & Setup](#installation--setup)
- [Database](#database)
- [Networking & Load Balancer](#networking--load-balancer)
- [Storage](#storage)
- [Backup & Restore](#backup--restore)
- [Security](#security)
- [Performance & Scaling](#performance--scaling)
- [Troubleshooting](#troubleshooting)
- [CI/CD](#cicd)

---

## General Questions

### Q: What is SFTPGo?

**A:** SFTPGo is a fully featured and highly configurable SFTP server with HTTP/S support. It can serve local filesystem, S3 (AWS or other compatible) and Google Cloud Storage backends. It provides a web-based admin interface and supports various authentication methods.

### Q: Why deploy SFTPGo on GKE?

**A:** Deploying on GKE provides:
- High availability through multiple replicas
- Auto-scaling capabilities
- Easy backup and disaster recovery
- Integration with Google Cloud services
- Professional-grade infrastructure
- Simplified management through Kubernetes

### Q: What are the costs involved?

**A:** Main costs include:
- GKE cluster (nodes)
- Persistent storage (GCE disks)
- Load balancer (external IP)
- Cloud SQL for PostgreSQL (if used)
- GCS for backups
- Network egress

Estimate your costs using the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator).

### Q: Can I use this in production?

**A:** Yes, this setup is designed for production use with:
- High availability (multiple replicas)
- Automated backups
- External PostgreSQL database
- Persistent storage
- Load balancing

However, always test thoroughly in a staging environment first.

---

## Installation & Setup

### Q: What are the minimum requirements?

**A:**
- GKE cluster with at least 2 nodes (n1-standard-2 or better)
- External PostgreSQL database (Cloud SQL or self-hosted)
- GCS bucket for backups
- Static IP address
- Basic knowledge of Kubernetes and GCP

### Q: How long does installation take?

**A:**
- Initial setup: 30-60 minutes
- Deployment: 5-10 minutes
- Total: About 1-2 hours for first-time setup

### Q: Do I need to use Cloud SQL or can I use my own PostgreSQL?

**A:** You can use either:
- **Cloud SQL**: Managed, automatic backups, easier setup
- **Self-hosted PostgreSQL**: More control, potentially lower cost
- **Other managed PostgreSQL**: AWS RDS, Azure Database, etc. (must be accessible from GKE)

### Q: Can I deploy this without GitLab CI/CD?

**A:** Yes! The GitLab CI/CD pipeline is optional. You can deploy manually using `kubectl` commands as shown in the installation guide.

### Q: What Kubernetes version is required?

**A:** Kubernetes 1.25 or later is required. This version adds support for the CronJob `timeZone` field used in the backup schedule. The manifests use stable API versions that work with recent Kubernetes releases.

---

## Database

### Q: Why use an external PostgreSQL database instead of running it in Kubernetes?

**A:** External databases (like Cloud SQL) provide:
- Automated backups
- High availability
- Automatic updates and patches
- Better performance
- Easier disaster recovery
- Separation of concerns

### Q: Can I use MySQL instead of PostgreSQL?

**A:** Yes, SFTPGo supports multiple databases:
- PostgreSQL (recommended)
- MySQL/MariaDB
- SQLite (not recommended for production)
- CockroachDB

Update the `SFTPGO_DATA_PROVIDER__DRIVER` in the ConfigMap accordingly.

### Q: How do I migrate data from SQLite to PostgreSQL?

**A:** SFTPGo provides migration tools. Check the [official documentation](https://github.com/drakkan/sftpgo/blob/main/docs/db-migration.md) for database migration procedures.

### Q: What if my database connection fails?

**A:** Check:
1. Database credentials in secrets are correct
2. Database is accessible from GKE cluster (firewall rules)
3. Database is running and accepting connections
4. Check pod logs: `kubectl logs -n sftpgo <pod-name>`

---

## Networking & Load Balancer

### Q: Why do I need a static IP?

**A:** Static IP provides:
- Consistent endpoint for users
- Easier DNS configuration
- Required for some firewall rules
- Better for production environments

### Q: How much does a static IP cost?

**A:** Google Cloud charges for:
- Reserved but unused IPs: ~$3-4/month
- IPs in use: Free (only pay for egress traffic)

### Q: Can I use an Ingress instead of LoadBalancer?

**A:** For HTTP, yes. For SFTP, you need a LoadBalancer (Layer 4) since Ingress only supports HTTP/HTTPS (Layer 7).

You can use both:
- LoadBalancer for SFTP
- Ingress for HTTP with SSL termination

### Q: How do I setup SSL/TLS?

**A:** Options:
1. **For HTTP**: Use Ingress with cert-manager for automatic Let's Encrypt certificates
2. **For SFTP**: Configure SFTPGo to use certificates (mount certificates as secrets)

### Q: What ports are exposed?

**A:**
- Port 22 (2022 internally): SFTP
- Port 80 (8080 internally): Web UI & API

---

## Storage

### Q: How much storage do I need?

**A:** Depends on your use case:
- **sftpgo-data** (100GB default): SFTPGo configuration and metadata
- **sftpgo-home** (500GB default): User files

Adjust based on your needs. You can start small and resize later.

### Q: Can I use different storage classes?

**A:** Yes! Available GKE storage classes:
- `standard-rwo`: Standard persistent disks (default)
- `premium-rwo`: SSD persistent disks (faster, more expensive)
- `standard`: Legacy, not recommended

Update `storageClassName` in `k8s/persistent-volume-claim.yaml`.

### Q: How do I resize a persistent volume?

**A:**
1. Edit the PVC: `kubectl edit pvc sftpgo-data -n sftpgo`
2. Update the storage size
3. Restart the pod

Note: Can only increase size, not decrease. The storage class must support volume expansion.

### Q: Can I use Google Cloud Storage (GCS) as the storage backend?

**A:** Yes! SFTPGo supports GCS as a storage backend. Configure it in the SFTPGo settings. This is different from the persistent volumes used for SFTPGo itself.

---

## Backup & Restore

### Q: What gets backed up?

**A:** The backup script backs up:
1. PostgreSQL database (complete dump)
2. SFTPGo data directory (`/srv/sftpgo`)
3. SFTPGo home directory (`/var/lib/sftpgo`)
4. Metadata file with backup information

### Q: Where are backups stored?

**A:** Backups are stored in Google Cloud Storage (GCS) in the bucket you specified. Organization:
```
gs://your-bucket/backups/
  ├── 2024-01-15/
  │   └── sftpgo-backup-20240115_020000.tar.gz
  ├── 2024-01-16/
  │   └── sftpgo-backup-20240116_020000.tar.gz
  └── ...
```

### Q: How long are backups retained?

**A:** Default: 30 days. Configure `BACKUP_RETENTION_DAYS` in `k8s/configmap.yaml`.

### Q: Can I backup manually?

**A:** Yes! Two ways:
1. **Local**: Run `./scripts/backup.sh` with proper environment variables
2. **GitLab CI/CD**: Trigger the `backup:manual` job

### Q: How do I restore from backup?

**A:**
```bash
./scripts/restore.sh gs://bucket/path/to/backup.tar.gz
```

Follow the prompts. You can restore:
- Database only: `--db-only`
- Data only: `--data-only`
- Both (default)

### Q: What happens during restore?

**A:**
1. Backup is downloaded from GCS
2. For database: drops and recreates the database, then restores data
3. For files: replaces SFTPGo data directories
4. SFTPGo pods are restarted

**Warning**: This overwrites existing data!

### Q: How can I test my backups?

**A:** Best practice:
1. Create a separate GKE cluster for testing
2. Run restore on the test cluster
3. Verify data integrity
4. Test SFTP connections and file access

---

## Security

### Q: How do I secure the admin interface?

**A:**
1. Use strong passwords in secrets
2. Setup Ingress with SSL/TLS
3. Restrict access with firewall rules
4. Enable 2FA in SFTPGo settings
5. Use OAuth2 or OIDC authentication

### Q: How are secrets managed?

**A:**
- Stored in Kubernetes Secrets
- Base64 encoded (not encrypted by default)
- For production: use GCP Secret Manager or Sealed Secrets
- Never commit secrets to git

### Q: Should I encrypt the persistent volumes?

**A:** Yes, for production:
1. GKE encrypts data at rest by default
2. For additional security, use customer-managed encryption keys (CMEK)
3. Configure in GCP console or via Terraform

### Q: How do I rotate credentials?

**A:**
1. Update secrets: `kubectl edit secret sftpgo-secrets -n sftpgo`
2. Restart pods: `kubectl rollout restart deployment/sftpgo -n sftpgo`

For database password rotation, update both the secret and the database.

### Q: Is network traffic encrypted?

**A:**
- **SFTP**: Encrypted by default
- **HTTP**: Use Ingress with TLS for web interface

---

## Performance & Scaling

### Q: How do I scale SFTPGo?

**A:** Update replicas:
```bash
kubectl scale deployment/sftpgo --replicas=3 -n sftpgo
```

Or edit `k8s/deployment.yaml` and apply.

### Q: What are the resource requirements?

**A:** Default (per pod):
- **Requests**: 500m CPU, 512Mi memory
- **Limits**: 2000m CPU, 2Gi memory

Adjust based on your workload in `k8s/deployment.yaml`.

### Q: Can SFTPGo auto-scale?

**A:** Yes! Create a HorizontalPodAutoscaler:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sftpgo-hpa
  namespace: sftpgo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sftpgo
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Q: How many concurrent users can it handle?

**A:** Depends on:
- Node resources
- Number of replicas
- Database performance
- Network bandwidth
- Storage I/O

With default setup (2 replicas, n1-standard-2): ~100-200 concurrent users. Scale up for more.

---

## Troubleshooting

### Q: Pods are in CrashLoopBackOff

**A:** Common causes:
1. Database connection failed - check credentials and connectivity
2. Invalid configuration - check ConfigMap and Secrets
3. Missing dependencies - check pod logs
4. Resource constraints - check node resources

Debug: `kubectl describe pod <pod-name> -n sftpgo`

### Q: External IP shows <pending>

**A:**
- Usually takes 2-5 minutes to provision
- Check: `kubectl describe service sftpgo-sftp -n sftpgo`
- Verify static IP is not already in use
- Ensure quotas are not exceeded

### Q: Can't connect to SFTP

**A:** Check:
1. External IP is assigned: `kubectl get svc -n sftpgo`
2. Firewall rules allow port 22
3. User credentials are correct
4. Pods are running: `kubectl get pods -n sftpgo`

### Q: Backup job fails

**A:** Common issues:
1. GCS credentials incorrect - check secret
2. Database connection failed - verify credentials
3. No pods available - check if deployment is running
4. Insufficient permissions - check service account roles

View logs: `kubectl logs -n sftpgo job/<job-name>`

### Q: High memory usage

**A:**
- Normal for file transfers
- Increase limits if pods are OOMKilled
- Check for memory leaks in logs
- Consider vertical or horizontal scaling

---

## CI/CD

### Q: Which CI/CD systems are supported?

**A:** The repository includes GitLab CI/CD, but you can adapt for:
- GitHub Actions
- Jenkins
- CircleCI
- Cloud Build
- Any CI/CD with kubectl and gcloud

### Q: Do I need to use CI/CD?

**A:** No, it's optional. You can deploy manually using kubectl commands.

### Q: How do I customize the pipeline?

**A:** Edit `.gitlab-ci.yml`:
- Add/remove stages
- Modify deployment logic
- Add testing steps
- Configure notifications

### Q: Can I deploy to multiple environments?

**A:** Yes! The pipeline includes:
- `deploy:dev` for development
- `deploy:prod` for production

Customize for staging, testing, etc.

### Q: How do I rollback a deployment?

**A:**
```bash
kubectl rollout undo deployment/sftpgo -n sftpgo
```

Or restore from a previous backup.

---

## Additional Questions?

If your question isn't answered here:

1. Check the [Installation Guide](INSTALLATION_EN.md)
2. Review [SFTPGo Documentation](https://github.com/drakkan/sftpgo/blob/main/docs/README.md)
3. Check Kubernetes and GKE documentation
4. Review logs: `kubectl logs -n sftpgo <pod-name>`
5. Check events: `kubectl get events -n sftpgo`

---

**Last Updated**: 2024
**Version**: 1.0
