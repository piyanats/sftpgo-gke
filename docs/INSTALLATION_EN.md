# SFTPGo GKE Installation Guide (English)

Complete step-by-step guide for deploying SFTPGo on Google Kubernetes Engine with external PostgreSQL database.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Database Configuration](#database-configuration)
4. [GCS Backup Setup](#gcs-backup-setup)
5. [Reserve Static IP](#reserve-static-ip)
6. [Configure Kubernetes Secrets](#configure-kubernetes-secrets)
7. [Deploy to GKE](#deploy-to-gke)
8. [Verify Deployment](#verify-deployment)
9. [Setup GitLab CI/CD](#setup-gitlab-cicd)
10. [Backup and Restore](#backup-and-restore)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

- **Google Cloud SDK** (`gcloud`) - [Installation Guide](https://cloud.google.com/sdk/docs/install)
- **kubectl** - Kubernetes command-line tool
- **Git** - Version control
- **GitLab account** - For CI/CD (optional but recommended)

### Required Services

1. **GKE Cluster**
   - Kubernetes version 1.24 or later
   - At least 2 nodes
   - Recommended: n1-standard-2 or better

2. **External PostgreSQL Database**
   - PostgreSQL 12 or later
   - Options:
     - Google Cloud SQL for PostgreSQL
     - Self-hosted PostgreSQL
     - Managed PostgreSQL from other providers

3. **Google Cloud Storage Bucket**
   - For storing backups
   - Should be in the same region as GKE cluster for better performance

### Required Permissions

Your GCP service account needs:
- Kubernetes Engine Admin
- Storage Admin
- Compute Network Admin (for static IP)
- Cloud SQL Client (if using Cloud SQL)

---

## Initial Setup

### 1. Clone the Repository

```bash
git clone <your-repository-url>
cd sftpgo-gke
```

### 2. Set Environment Variables

Create a file named `.env` (don't commit this file!):

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="asia-southeast1"
export GKE_CLUSTER_NAME="your-gke-cluster"
export GKE_ZONE="asia-southeast1-a"
```

Load the environment:

```bash
source .env
```

### 3. Authenticate with GCP

```bash
gcloud auth login
gcloud config set project $GCP_PROJECT_ID
```

### 4. Connect to GKE Cluster

```bash
gcloud container clusters get-credentials $GKE_CLUSTER_NAME \
  --zone=$GKE_ZONE \
  --project=$GCP_PROJECT_ID
```

Verify connection:

```bash
kubectl cluster-info
kubectl get nodes
```

---

## Database Configuration

### Option 1: Google Cloud SQL for PostgreSQL

#### Create Cloud SQL Instance

```bash
gcloud sql instances create sftpgo-db \
  --database-version=POSTGRES_14 \
  --tier=db-custom-2-7680 \
  --region=$GCP_REGION \
  --network=default \
  --no-assign-ip
```

#### Create Database and User

```bash
# Create database
gcloud sql databases create sftpgo --instance=sftpgo-db

# Create user
gcloud sql users create sftpgo \
  --instance=sftpgo-db \
  --password=YOUR_SECURE_PASSWORD
```

#### Get Connection Details

```bash
# Get private IP
gcloud sql instances describe sftpgo-db --format="value(ipAddresses[0].ipAddress)"
```

Save these details for later:
- Host: (private IP from above)
- Port: 5432
- Database: sftpgo
- User: sftpgo
- Password: YOUR_SECURE_PASSWORD

### Option 2: External PostgreSQL

If using external PostgreSQL:

1. Ensure the database is accessible from your GKE cluster
2. Create a database named `sftpgo`
3. Create a user with full permissions on the database
4. Note down: host, port, database name, username, and password

---

## GCS Backup Setup

### 1. Create GCS Bucket

```bash
gsutil mb -p $GCP_PROJECT_ID -c STANDARD -l $GCP_REGION gs://sftpgo-backups-$GCP_PROJECT_ID
```

### 2. Create Service Account for Backups

```bash
# Create service account
gcloud iam service-accounts create sftpgo-backup \
  --display-name="SFTPGo Backup Service Account"

# Grant Storage Admin role
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:sftpgo-backup@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Create and download key
gcloud iam service-accounts keys create sftpgo-backup-key.json \
  --iam-account=sftpgo-backup@$GCP_PROJECT_ID.iam.gserviceaccount.com
```

**Important**: Keep `sftpgo-backup-key.json` secure and don't commit it to git!

---

## Reserve Static IP

### Create Static IP Address

```bash
chmod +x scripts/reserve-static-ip.sh
./scripts/reserve-static-ip.sh sftpgo-static-ip asia-southeast1
```

The script will output your static IP address. Save this value.

### Alternative Manual Method

```bash
# Reserve IP
gcloud compute addresses create sftpgo-static-ip \
  --region=$GCP_REGION

# Get the IP address
gcloud compute addresses describe sftpgo-static-ip \
  --region=$GCP_REGION \
  --format="get(address)"
```

---

## Configure Kubernetes Secrets

### 1. Update Database Secrets

Edit `k8s/secret.yaml`:

```yaml
stringData:
  POSTGRES_HOST: "10.128.0.3"  # Your PostgreSQL host
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "sftpgo"
  POSTGRES_USER: "sftpgo"
  POSTGRES_PASSWORD: "your-secure-password"  # Change this!

  SFTPGO_ADMIN_USERNAME: "admin"
  SFTPGO_ADMIN_PASSWORD: "your-admin-password"  # Change this!
  SFTPGO_JWT_SECRET: "your-jwt-secret-key"  # Change this!
```

### 2. Update GCS Backup Credentials

Replace the content of `credentials.json` in `k8s/secret.yaml` with the content of `sftpgo-backup-key.json`:

```bash
cat sftpgo-backup-key.json
```

Copy the entire JSON content and paste it into the `credentials.json` field in `k8s/secret.yaml`.

### 3. Update ConfigMap

Edit `k8s/configmap.yaml`:

```yaml
data:
  GCS_BUCKET_NAME: "gs://sftpgo-backups-your-project-id"
  BACKUP_RETENTION_DAYS: "30"  # Adjust as needed
```

### 4. Update Service with Static IP

Edit `k8s/service.yaml`:

Find the `sftpgo-sftp` service and uncomment/set the `loadBalancerIP`:

```yaml
spec:
  type: LoadBalancer
  loadBalancerIP: "35.123.456.789"  # Your static IP from earlier step
```

---

## Deploy to GKE

### 1. Create Namespace

```bash
kubectl apply -f k8s/namespace.yaml
```

Verify:

```bash
kubectl get namespace sftpgo
```

### 2. Apply Secrets and ConfigMap

```bash
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/configmap.yaml
```

Verify:

```bash
kubectl get secrets -n sftpgo
kubectl get configmap -n sftpgo
```

### 3. Create Persistent Volumes

```bash
kubectl apply -f k8s/persistent-volume-claim.yaml
```

Wait for volumes to be bound:

```bash
kubectl get pvc -n sftpgo
```

### 4. Deploy SFTPGo

```bash
kubectl apply -f k8s/deployment.yaml
```

Monitor deployment:

```bash
kubectl rollout status deployment/sftpgo -n sftpgo
```

Check pods:

```bash
kubectl get pods -n sftpgo
```

### 5. Create Services

```bash
kubectl apply -f k8s/service.yaml
```

Get external IP (may take a few minutes):

```bash
kubectl get service sftpgo-sftp -n sftpgo -w
```

### 6. Setup Backup CronJob

First, update the backup script in ConfigMap:

```bash
kubectl create configmap backup-scripts \
  --from-file=backup.sh=scripts/backup.sh \
  --namespace=sftpgo \
  --dry-run=client -o yaml | kubectl apply -f -
```

Then apply the CronJob:

```bash
kubectl apply -f k8s/cronjob-backup.yaml
```

Verify:

```bash
kubectl get cronjob -n sftpgo
```

---

## Verify Deployment

### 1. Check All Resources

```bash
kubectl get all -n sftpgo
```

### 2. Check Logs

```bash
# Get pod name
POD_NAME=$(kubectl get pods -n sftpgo -l app=sftpgo -o jsonpath='{.items[0].metadata.name}')

# View logs
kubectl logs -n sftpgo $POD_NAME --tail=100 -f
```

### 3. Access Web Interface

Get the web service external IP:

```bash
kubectl get service sftpgo-web -n sftpgo
```

Access the web interface:

```
http://<EXTERNAL-IP>
```

Login with the admin credentials you set in the secrets.

### 4. Test SFTP Connection

```bash
# Get SFTP external IP
SFTP_IP=$(kubectl get service sftpgo-sftp -n sftpgo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test connection
sftp -P 22 admin@$SFTP_IP
```

---

## Setup GitLab CI/CD

### 1. Add GitLab Variables

In your GitLab project, go to **Settings > CI/CD > Variables** and add:

| Variable | Value | Protected | Masked |
|----------|-------|-----------|--------|
| `GCP_PROJECT_ID` | your-project-id | ✓ | ✗ |
| `GCP_REGION` | asia-southeast1 | ✗ | ✗ |
| `GKE_CLUSTER_NAME` | your-cluster-name | ✗ | ✗ |
| `GKE_ZONE` | asia-southeast1-a | ✗ | ✗ |
| `GCP_SERVICE_KEY` | Base64 encoded service account key | ✓ | ✓ |

### 2. Create Service Account for GitLab

```bash
# Create service account
gcloud iam service-accounts create gitlab-ci \
  --display-name="GitLab CI/CD Service Account"

# Grant necessary roles
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:gitlab-ci@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:gitlab-ci@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# Create key
gcloud iam service-accounts keys create gitlab-ci-key.json \
  --iam-account=gitlab-ci@$GCP_PROJECT_ID.iam.gserviceaccount.com

# Base64 encode for GitLab
cat gitlab-ci-key.json | base64 -w 0
```

Copy the base64 output and add it as `GCP_SERVICE_KEY` variable in GitLab.

### 3. Push to GitLab

```bash
git add .
git commit -m "Initial SFTPGo GKE deployment"
git push origin main
```

### 4. Trigger Pipeline

The pipeline will run automatically. You can also:

- Go to **CI/CD > Pipelines**
- Click **Run Pipeline**
- Select the deployment job you want to run

---

## Backup and Restore

### Manual Backup

#### Using kubectl

```bash
# Get credentials from secrets
export POSTGRES_HOST=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_HOST}' | base64 -d)
export POSTGRES_PORT=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_PORT}' | base64 -d)
export POSTGRES_DB=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
export POSTGRES_USER=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
export POSTGRES_PASSWORD=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
export GCS_BUCKET=$(kubectl get configmap sftpgo-config -n sftpgo -o jsonpath='{.data.GCS_BUCKET_NAME}')
export RETENTION_DAYS=$(kubectl get configmap sftpgo-config -n sftpgo -o jsonpath='{.data.BACKUP_RETENTION_DAYS}')
export NAMESPACE=sftpgo

# Run backup
./scripts/backup.sh
```

#### Using GitLab CI/CD

- Go to **CI/CD > Pipelines**
- Click **Run Pipeline**
- Run the `backup:manual` job

### Restore from Backup

#### List Available Backups

```bash
gsutil ls gs://sftpgo-backups-$GCP_PROJECT_ID/backups/
```

#### Restore

```bash
# Set the backup file
export BACKUP_FILE="gs://sftpgo-backups-project/backups/2024-01-15/sftpgo-backup-20240115_120000.tar.gz"

# Get credentials
export POSTGRES_HOST=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_HOST}' | base64 -d)
export POSTGRES_PORT=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_PORT}' | base64 -d)
export POSTGRES_DB=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
export POSTGRES_USER=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
export POSTGRES_PASSWORD=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
export NAMESPACE=sftpgo

# Run restore
./scripts/restore.sh $BACKUP_FILE
```

**Warning**: This will overwrite existing data!

### Automated Daily Backups

Backups run automatically every day at 2:00 AM UTC via the CronJob.

Check backup job history:

```bash
kubectl get jobs -n sftpgo
```

View backup job logs:

```bash
kubectl logs -n sftpgo job/sftpgo-backup-<job-id>
```

---

## Troubleshooting

### Pods Not Starting

Check pod status:

```bash
kubectl describe pod <pod-name> -n sftpgo
```

Common issues:
- PVC not bound: Check if PVCs are created and bound
- Image pull errors: Verify image name and registry access
- Secrets not found: Ensure secrets are created in the correct namespace

### Database Connection Issues

Check logs:

```bash
kubectl logs -n sftpgo <pod-name>
```

Verify database connectivity from pod:

```bash
kubectl exec -it -n sftpgo <pod-name> -- /bin/sh
# Inside pod
nc -zv <postgres-host> 5432
```

### External IP Not Assigned

Check service:

```bash
kubectl describe service sftpgo-sftp -n sftpgo
```

Ensure:
- Load balancer is being created
- Static IP is not already in use
- Region matches your cluster region

### Backup Job Failing

Check CronJob:

```bash
kubectl get cronjob -n sftpgo
kubectl get jobs -n sftpgo
```

View logs:

```bash
# Get the latest backup job
JOB_NAME=$(kubectl get jobs -n sftpgo -l app=sftpgo-backup --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

# View logs
kubectl logs -n sftpgo job/$JOB_NAME
```

Common issues:
- GCS credentials incorrect
- PostgreSQL connection failed
- Insufficient permissions

### View All Events

```bash
kubectl get events -n sftpgo --sort-by='.lastTimestamp'
```

---

## Next Steps

1. **Configure DNS**: Point your domain to the static IP
2. **Setup SSL/TLS**: Configure certificates for secure connections
3. **Configure Users**: Create SFTP users via web interface
4. **Monitor Resources**: Set up monitoring and alerting
5. **Test Backups**: Verify backup and restore procedures
6. **Security Hardening**: Review and implement security best practices

---

## Additional Resources

- [SFTPGo Official Documentation](https://github.com/drakkan/sftpgo/blob/main/docs/README.md)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [FAQ (English)](FAQ_EN.md)
- [FAQ (Thai)](FAQ_TH.md)

---

## Support

For issues and questions:
- Check the [FAQ](FAQ_EN.md)
- Review SFTPGo documentation
- Check Kubernetes events and logs
- Contact your system administrator
