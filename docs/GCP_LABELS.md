# GCP Resource Labels

All GCP resources in this project are labeled with the following labels for better resource management, cost tracking, and organization.

## Standard Labels

All resources should include these labels:

| Label | Value | Description |
|-------|-------|-------------|
| `app` | `sftpgo` | Application name |
| `project` | `sftpgo-gke` | Project identifier |

## Resources with Labels

### 1. Compute Resources

#### Static IP Address
```bash
gcloud compute addresses create sftpgo-static-ip \
  --region=asia-southeast1 \
  --labels=app=sftpgo,project=sftpgo-gke
```

#### Persistent Disks (via Kubernetes)
Automatically labeled through PVC annotations:
```yaml
annotations:
  volume.beta.kubernetes.io/storage-labels: "app=sftpgo,project=sftpgo-gke"
```

### 2. Storage Resources

#### GCS Buckets
```bash
gsutil label ch -l app:sftpgo gs://sftpgo-backups-project-id
gsutil label ch -l project:sftpgo-gke gs://sftpgo-backups-project-id
```

### 3. Database Resources

#### Cloud SQL Instance
```bash
gcloud sql instances create sftpgo-db \
  --labels=app=sftpgo,project=sftpgo-gke \
  [other options...]
```

### 4. Kubernetes Resources

All Kubernetes resources include labels in their metadata:
```yaml
metadata:
  labels:
    app: sftpgo
    project: sftpgo-gke
```

This includes:
- Namespaces
- Deployments
- Services
- PersistentVolumeClaims
- ConfigMaps
- Secrets
- CronJobs

### 5. Load Balancers

Load balancers inherit labels from their associated Kubernetes Services through annotations.

## Benefits of Labeling

### 1. Cost Tracking
- View costs broken down by application
- Track spending for specific projects
- Create cost allocation reports

Example query in Cloud Billing:
```sql
SELECT labels.value AS app, SUM(cost)
FROM billing_data
WHERE labels.key = 'app'
GROUP BY app
```

### 2. Resource Organization
- Filter resources in Cloud Console by labels
- Find all resources related to a specific application
- Organize resources across multiple projects

Example gcloud filter:
```bash
gcloud compute instances list --filter="labels.app=sftpgo"
```

### 3. Automation
- Apply policies to labeled resources
- Automate resource management tasks
- Create monitoring alerts for specific labels

### 4. Access Control
- Create IAM policies based on labels
- Restrict access to resources by label
- Audit resource access by application

## Viewing Labels

### List Resources by Label

#### Compute Resources
```bash
# List all compute addresses with app=sftpgo
gcloud compute addresses list --filter="labels.app=sftpgo"

# List all disks with project=sftpgo-gke
gcloud compute disks list --filter="labels.project=sftpgo-gke"
```

#### Cloud SQL
```bash
# List Cloud SQL instances with labels
gcloud sql instances list --filter="settings.userLabels.app=sftpgo"
```

#### GCS Buckets
```bash
# List bucket labels
gsutil label get gs://sftpgo-backups-project-id
```

### Kubernetes Resources
```bash
# List all resources with specific label
kubectl get all -n sftpgo -l app=sftpgo
kubectl get all -n sftpgo -l project=sftpgo-gke
```

## Cost Analysis Example

### Using Cloud Console
1. Go to Cloud Billing → Reports
2. Filter by Labels → app:sftpgo
3. View breakdown by service and resource

### Using gcloud
```bash
# Export billing data with labels
gcloud billing accounts list
gcloud beta billing accounts get-iam-policy ACCOUNT_ID
```

### Using BigQuery (if billing export is enabled)
```sql
SELECT
  labels.value AS app,
  service.description AS service,
  SUM(cost) AS total_cost
FROM
  `project.dataset.gcp_billing_export`
WHERE
  labels.key = 'app'
  AND labels.value = 'sftpgo'
GROUP BY
  app, service
ORDER BY
  total_cost DESC
```

## Label Management Best Practices

### 1. Consistent Naming
- Use lowercase for label keys and values
- Use hyphens (-) instead of underscores (_)
- Keep label names short and descriptive

### 2. Standard Labels
Always include these labels on all resources:
- `app`: Application name
- `project`: Project identifier
- Optional: `environment` (dev, staging, prod)
- Optional: `owner` (team or individual)
- Optional: `cost-center`

### 3. Label Limitations
- Maximum 64 labels per resource
- Key length: 1-63 characters
- Value length: 0-63 characters
- Keys and values can only contain lowercase letters, numbers, hyphens, and underscores

### 4. Automation
Use Infrastructure as Code (Terraform, etc.) to ensure all resources are properly labeled:

```hcl
# Terraform example
resource "google_compute_address" "sftpgo_ip" {
  name   = "sftpgo-static-ip"
  region = "asia-southeast1"

  labels = {
    app     = "sftpgo"
    project = "sftpgo-gke"
  }
}
```

## Updating Labels

### Add/Update Labels on Existing Resources

#### Compute Address
```bash
gcloud compute addresses update sftpgo-static-ip \
  --region=asia-southeast1 \
  --update-labels=app=sftpgo,project=sftpgo-gke
```

#### Cloud SQL Instance
```bash
gcloud sql instances patch sftpgo-db \
  --labels=app=sftpgo,project=sftpgo-gke
```

#### GCS Bucket
```bash
gsutil label ch -l app:sftpgo gs://bucket-name
gsutil label ch -l project:sftpgo-gke gs://bucket-name
```

### Remove Labels
```bash
# Compute resources
gcloud compute addresses update sftpgo-static-ip \
  --region=asia-southeast1 \
  --remove-labels=key1,key2

# GCS buckets
gsutil label ch -d key1 gs://bucket-name
```

## Monitoring and Alerts

Create alerts based on labeled resources:

```yaml
# Example Cloud Monitoring alert
displayName: "High CPU on SFTPGo resources"
conditions:
  - displayName: "CPU usage > 80%"
    conditionThreshold:
      filter: |
        resource.type = "gce_instance"
        AND resource.labels.app = "sftpgo"
      comparison: COMPARISON_GT
      thresholdValue: 0.8
```

## Compliance and Governance

Labels help with compliance requirements:
- Track resources by compliance framework
- Identify resources for security audits
- Manage data residency requirements

Example:
```yaml
labels:
  app: sftpgo
  project: sftpgo-gke
  compliance: gdpr
  data-classification: confidential
  data-residency: asia-southeast
```

---

For more information, see:
- [Google Cloud Labels Documentation](https://cloud.google.com/resource-manager/docs/creating-managing-labels)
- [Kubernetes Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
