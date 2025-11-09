# SFTPGo on Google Kubernetes Engine (GKE)

A complete deployment solution for running SFTPGo on Google Kubernetes Engine with external PostgreSQL database, automated backups to Google Cloud Storage, and CI/CD integration with GitLab.

## Language / ภาษา

- [English Documentation](docs/INSTALLATION_EN.md)
- [เอกสารภาษาไทย](docs/INSTALLATION_TH.md)

## Features

- ✅ **Production-ready deployment** on Google Kubernetes Engine
- ✅ **External PostgreSQL** database support
- ✅ **Static IP address** configuration for consistent endpoint
- ✅ **Automated daily backups** to Google Cloud Storage
- ✅ **Backup and restore scripts** for disaster recovery
- ✅ **GitLab CI/CD pipeline** for automated deployment
- ✅ **High availability** with multiple replicas
- ✅ **Persistent storage** for SFTPGo data and user files
- ✅ **Multi-protocol support**: SFTP, FTP, WebDAV
- ✅ **Web admin interface** for easy management

## Quick Start

### Prerequisites

- Google Cloud Platform account
- GKE cluster up and running
- External PostgreSQL database
- Google Cloud Storage bucket for backups
- `gcloud` CLI installed and configured
- `kubectl` installed
- GitLab account (for CI/CD)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd sftpgo-gke
   ```

2. **Reserve a static IP address**
   ```bash
   chmod +x scripts/reserve-static-ip.sh
   ./scripts/reserve-static-ip.sh sftpgo-static-ip asia-southeast1
   ```

3. **Configure secrets**

   Edit `k8s/secret.yaml` and update:
   - PostgreSQL connection details
   - SFTPGo admin credentials
   - GCS service account credentials

4. **Update ConfigMap**

   Edit `k8s/configmap.yaml` and update:
   - GCS bucket name
   - Backup retention settings

5. **Deploy to GKE**
   ```bash
   # Create namespace
   kubectl apply -f k8s/namespace.yaml

   # Apply secrets (make sure to update them first!)
   kubectl apply -f k8s/secret.yaml

   # Apply ConfigMap
   kubectl apply -f k8s/configmap.yaml

   # Create persistent volumes
   kubectl apply -f k8s/persistent-volume-claim.yaml

   # Deploy SFTPGo
   kubectl apply -f k8s/deployment.yaml

   # Create services
   kubectl apply -f k8s/service.yaml

   # Set up backup CronJob
   kubectl apply -f k8s/cronjob-backup.yaml
   ```

6. **Get external IP**
   ```bash
   kubectl get service sftpgo-sftp -n sftpgo
   ```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Google Cloud Platform                   │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              Google Kubernetes Engine (GKE)            │ │
│  │                                                          │ │
│  │  ┌──────────────┐         ┌──────────────┐            │ │
│  │  │  SFTPGo Pod  │◄────────┤  SFTPGo Pod  │            │ │
│  │  │   (Replica)  │         │   (Replica)  │            │ │
│  │  └───────┬──────┘         └──────┬───────┘            │ │
│  │          │                       │                      │ │
│  │          └───────────┬───────────┘                      │ │
│  │                      │                                  │ │
│  │              ┌───────▼────────┐                         │ │
│  │              │ Load Balancer  │                         │ │
│  │              │  (Static IP)   │                         │ │
│  │              └───────┬────────┘                         │ │
│  │                      │                                  │ │
│  │              ┌───────▼────────┐                         │ │
│  │              │ Persistent     │                         │ │
│  │              │ Volumes (GCE)  │                         │ │
│  │              └────────────────┘                         │ │
│  │                                                          │ │
│  │  ┌──────────────────────────────────────────┐          │ │
│  │  │  Backup CronJob (Daily at 2 AM UTC)      │          │ │
│  │  └──────────────────┬───────────────────────┘          │ │
│  │                     │                                   │ │
│  └─────────────────────┼───────────────────────────────────┘ │
│                        │                                     │
│  ┌─────────────────────▼───────────┐                        │
│  │  Google Cloud Storage (GCS)     │                        │
│  │  Backup Bucket                  │                        │
│  └─────────────────────────────────┘                        │
│                                                              │
│  ┌──────────────────────────────────┐                       │
│  │  External PostgreSQL Database    │                       │
│  │  (Cloud SQL or self-hosted)      │                       │
│  └──────────────────────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
```

## Project Structure

```
sftpgo-gke/
├── .gitlab-ci.yml              # GitLab CI/CD pipeline
├── Dockerfile.backup           # Docker image for backup jobs
├── README.md                   # This file
├── docs/
│   ├── INSTALLATION_EN.md      # English installation guide
│   ├── INSTALLATION_TH.md      # Thai installation guide
│   ├── FAQ_EN.md               # English FAQ
│   └── FAQ_TH.md               # Thai FAQ
├── k8s/
│   ├── namespace.yaml          # Kubernetes namespace
│   ├── configmap.yaml          # Configuration
│   ├── secret.yaml             # Secrets (credentials)
│   ├── persistent-volume-claim.yaml  # Storage claims
│   ├── deployment.yaml         # SFTPGo deployment
│   ├── service.yaml            # Load balancer services
│   └── cronjob-backup.yaml     # Backup CronJob
└── scripts/
    ├── reserve-static-ip.sh    # Reserve GCP static IP
    ├── backup.sh               # Backup script
    └── restore.sh              # Restore script
```

## Documentation

- [Installation Guide (English)](docs/INSTALLATION_EN.md)
- [Installation Guide (Thai)](docs/INSTALLATION_TH.md)
- [FAQ (English)](docs/FAQ_EN.md)
- [FAQ (Thai)](docs/FAQ_TH.md)

## Support

For issues and questions:
- Check the [FAQ (English)](docs/FAQ_EN.md) or [FAQ (Thai)](docs/FAQ_TH.md)
- Review the installation guides
- Check SFTPGo official documentation: https://github.com/drakkan/sftpgo

## License

This deployment configuration is provided as-is for use with SFTPGo.

SFTPGo itself is licensed under AGPL-3.0. See the [SFTPGo repository](https://github.com/drakkan/sftpgo) for more information.
