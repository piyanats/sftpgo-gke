# คู่มือการติดตั้ง SFTPGo บน GKE (ภาษาไทย)

คู่มือทีละขั้นตอนสำหรับการติดตั้ง SFTPGo บน Google Kubernetes Engine พร้อมฐานข้อมูล PostgreSQL ภายนอก

## สารบัญ

1. [ข้อกำหนดเบื้องต้น](#ข้อกำหนดเบื้องต้น)
2. [การตั้งค่าเริ่มต้น](#การตั้งค่าเริ่มต้น)
3. [การตั้งค่าฐานข้อมูล](#การตั้งค่าฐานข้อมูล)
4. [การตั้งค่า GCS สำหรับสำรองข้อมูล](#การตั้งค่า-gcs-สำหรับสำรองข้อมูล)
5. [การจอง Static IP](#การจอง-static-ip)
6. [การตั้งค่า Kubernetes Secrets](#การตั้งค่า-kubernetes-secrets)
7. [การติดตั้งบน GKE](#การติดตั้งบน-gke)
8. [การตรวจสอบการติดตั้ง](#การตรวจสอบการติดตั้ง)
9. [การตั้งค่า GitLab CI/CD](#การตั้งค่า-gitlab-cicd)
10. [การสำรองและกู้คืนข้อมูล](#การสำรองและกู้คืนข้อมูล)
11. [การแก้ไขปัญหา](#การแก้ไขปัญหา)

---

## ข้อกำหนดเบื้องต้น

### เครื่องมือที่จำเป็น

- **Google Cloud SDK** (`gcloud`) - [คู่มือการติดตั้ง](https://cloud.google.com/sdk/docs/install)
- **kubectl** - เครื่องมือจัดการ Kubernetes
- **Git** - ระบบควบคุมเวอร์ชัน
- **บัญชี GitLab** - สำหรับ CI/CD (ไม่บังคับ แต่แนะนำ)

### บริการที่จำเป็น

1. **GKE Cluster**
   - Kubernetes เวอร์ชัน 1.24 ขึ้นไป
   - มี node อย่างน้อย 2 ตัว
   - แนะนำ: n1-standard-2 หรือดีกว่า

2. **ฐานข้อมูล PostgreSQL ภายนอก**
   - PostgreSQL 12 ขึ้นไป
   - ตัวเลือก:
     - Google Cloud SQL for PostgreSQL
     - PostgreSQL ที่ติดตั้งเอง
     - PostgreSQL แบบ managed จากผู้ให้บริการอื่น

3. **Google Cloud Storage Bucket**
   - สำหรับเก็บข้อมูลสำรอง
   - ควรอยู่ใน region เดียวกับ GKE cluster เพื่อประสิทธิภาพที่ดีขึ้น

### สิทธิ์ที่จำเป็น

Service account ของ GCP ต้องมี:
- Kubernetes Engine Admin
- Storage Admin
- Compute Network Admin (สำหรับ static IP)
- Cloud SQL Client (ถ้าใช้ Cloud SQL)

---

## การตั้งค่าเริ่มต้น

### 1. Clone Repository

```bash
git clone <url-repository-ของคุณ>
cd sftpgo-gke
```

### 2. ตั้งค่าตัวแปรสภาพแวดล้อม

สร้างไฟล์ชื่อ `.env` (อย่า commit ไฟล์นี้!):

```bash
export GCP_PROJECT_ID="project-id-ของคุณ"
export GCP_REGION="asia-southeast1"
export GKE_CLUSTER_NAME="ชื่อ-gke-cluster-ของคุณ"
export GKE_ZONE="asia-southeast1-a"
```

โหลดตัวแปรสภาพแวดล้อม:

```bash
source .env
```

### 3. ยืนยันตัวตนกับ GCP

```bash
gcloud auth login
gcloud config set project $GCP_PROJECT_ID
```

### 4. เชื่อมต่อกับ GKE Cluster

```bash
gcloud container clusters get-credentials $GKE_CLUSTER_NAME \
  --zone=$GKE_ZONE \
  --project=$GCP_PROJECT_ID
```

ตรวจสอบการเชื่อมต่อ:

```bash
kubectl cluster-info
kubectl get nodes
```

---

## การตั้งค่าฐานข้อมูล

### ตัวเลือกที่ 1: Google Cloud SQL for PostgreSQL

#### สร้าง Cloud SQL Instance

```bash
gcloud sql instances create sftpgo-db \
  --database-version=POSTGRES_14 \
  --tier=db-custom-2-7680 \
  --region=$GCP_REGION \
  --network=default \
  --no-assign-ip \
  --labels=app=sftpgo,project=sftpgo-gke
```

#### สร้างฐานข้อมูลและผู้ใช้

```bash
# สร้างฐานข้อมูล
gcloud sql databases create sftpgo --instance=sftpgo-db

# สร้างผู้ใช้
gcloud sql users create sftpgo \
  --instance=sftpgo-db \
  --password=รหัสผ่านที่ปลอดภัยของคุณ
```

#### รับข้อมูลการเชื่อมต่อ

```bash
# รับ private IP
gcloud sql instances describe sftpgo-db --format="value(ipAddresses[0].ipAddress)"
```

บันทึกข้อมูลเหล่านี้ไว้:
- Host: (private IP จากด้านบน)
- Port: 5432
- Database: sftpgo
- User: sftpgo
- Password: รหัสผ่านที่ปลอดภัยของคุณ

### ตัวเลือกที่ 2: PostgreSQL ภายนอก

หากใช้ PostgreSQL ภายนอก:

1. ตรวจสอบว่าฐานข้อมูลสามารถเข้าถึงได้จาก GKE cluster
2. สร้างฐานข้อมูลชื่อ `sftpgo`
3. สร้างผู้ใช้ที่มีสิทธิ์เต็มในฐานข้อมูล
4. บันทึก: host, port, ชื่อฐานข้อมูล, username และ password

---

## การตั้งค่า GCS สำหรับสำรองข้อมูล

### 1. สร้าง GCS Bucket

```bash
gsutil mb -p $GCP_PROJECT_ID -c STANDARD -l $GCP_REGION gs://sftpgo-backups-$GCP_PROJECT_ID

# เพิ่ม labels ให้กับ bucket
gsutil label ch -l app:sftpgo gs://sftpgo-backups-$GCP_PROJECT_ID
gsutil label ch -l project:sftpgo-gke gs://sftpgo-backups-$GCP_PROJECT_ID
```

### 2. สร้าง Service Account สำหรับสำรองข้อมูล

```bash
# สร้าง service account
gcloud iam service-accounts create sftpgo-backup \
  --display-name="SFTPGo Backup Service Account"

# กำหนด Storage Admin role
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:sftpgo-backup@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# สร้างและดาวน์โหลด key
gcloud iam service-accounts keys create sftpgo-backup-key.json \
  --iam-account=sftpgo-backup@$GCP_PROJECT_ID.iam.gserviceaccount.com
```

**สำคัญ**: เก็บรักษา `sftpgo-backup-key.json` ให้ปลอดภัย และอย่า commit ลง git!

---

## การจอง Static IP

### สร้าง Static IP Address

```bash
chmod +x scripts/reserve-static-ip.sh
./scripts/reserve-static-ip.sh sftpgo-static-ip asia-southeast1
```

สคริปต์จะแสดง static IP address ของคุณ บันทึกค่านี้ไว้

### วิธีแบบ Manual

```bash
# จอง IP พร้อม labels
gcloud compute addresses create sftpgo-static-ip \
  --region=$GCP_REGION \
  --labels=app=sftpgo,project=sftpgo-gke

# รับค่า IP address
gcloud compute addresses describe sftpgo-static-ip \
  --region=$GCP_REGION \
  --format="get(address)"
```

---

## การตั้งค่า Kubernetes Secrets

### 1. อัปเดต Database Secrets

แก้ไข `k8s/secret.yaml`:

```yaml
stringData:
  POSTGRES_HOST: "10.128.0.3"  # PostgreSQL host ของคุณ
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "sftpgo"
  POSTGRES_USER: "sftpgo"
  POSTGRES_PASSWORD: "รหัสผ่านที่ปลอดภัย"  # เปลี่ยนค่านี้!

  SFTPGO_ADMIN_USERNAME: "admin"
  SFTPGO_ADMIN_PASSWORD: "รหัสผ่าน-admin"  # เปลี่ยนค่านี้!
  SFTPGO_JWT_SECRET: "jwt-secret-key"  # เปลี่ยนค่านี้!
```

### 2. อัปเดต GCS Backup Credentials

แทนที่เนื้อหาของ `credentials.json` ใน `k8s/secret.yaml` ด้วยเนื้อหาของ `sftpgo-backup-key.json`:

```bash
cat sftpgo-backup-key.json
```

คัดลอก JSON ทั้งหมดและวางในฟิลด์ `credentials.json` ใน `k8s/secret.yaml`

### 3. อัปเดต ConfigMap

แก้ไข `k8s/configmap.yaml`:

```yaml
data:
  GCS_BUCKET_NAME: "gs://sftpgo-backups-your-project-id"
  BACKUP_RETENTION_DAYS: "30"  # ปรับตามต้องการ
```

### 4. อัปเดต Service ด้วย Static IP

แก้ไข `k8s/service.yaml`:

หา service `sftpgo-sftp` และเอาคอมเมนต์ออก/ตั้งค่า `loadBalancerIP`:

```yaml
spec:
  type: LoadBalancer
  loadBalancerIP: "35.123.456.789"  # Static IP จากขั้นตอนก่อนหน้า
```

---

## การติดตั้งบน GKE

### 1. สร้าง Namespace

```bash
kubectl apply -f k8s/namespace.yaml
```

ตรวจสอบ:

```bash
kubectl get namespace sftpgo
```

### 2. Apply Secrets และ ConfigMap

```bash
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/configmap.yaml
```

ตรวจสอบ:

```bash
kubectl get secrets -n sftpgo
kubectl get configmap -n sftpgo
```

### 3. สร้าง Persistent Volumes

```bash
kubectl apply -f k8s/persistent-volume-claim.yaml
```

รอให้ volumes ถูก bound:

```bash
kubectl get pvc -n sftpgo
```

### 4. ติดตั้ง SFTPGo

```bash
kubectl apply -f k8s/deployment.yaml
```

ติดตามการ deploy:

```bash
kubectl rollout status deployment/sftpgo -n sftpgo
```

ตรวจสอบ pods:

```bash
kubectl get pods -n sftpgo
```

### 5. สร้าง Services

```bash
kubectl apply -f k8s/service.yaml
```

รับ external IP (อาจใช้เวลาสักครู่):

```bash
kubectl get service sftpgo-sftp -n sftpgo -w
```

### 6. ตั้งค่า Backup CronJob

อันดับแรก อัปเดตสคริปต์สำรองข้อมูลใน ConfigMap:

```bash
kubectl create configmap backup-scripts \
  --from-file=backup.sh=scripts/backup.sh \
  --namespace=sftpgo \
  --dry-run=client -o yaml | kubectl apply -f -
```

จากนั้น apply CronJob:

```bash
kubectl apply -f k8s/cronjob-backup.yaml
```

ตรวจสอบ:

```bash
kubectl get cronjob -n sftpgo
```

---

## การตรวจสอบการติดตั้ง

### 1. ตรวจสอบทรัพยากรทั้งหมด

```bash
kubectl get all -n sftpgo
```

### 2. ตรวจสอบ Logs

```bash
# รับชื่อ pod
POD_NAME=$(kubectl get pods -n sftpgo -l app=sftpgo -o jsonpath='{.items[0].metadata.name}')

# ดู logs
kubectl logs -n sftpgo $POD_NAME --tail=100 -f
```

### 3. เข้าถึง Web Interface

รับ external IP ของ web service:

```bash
kubectl get service sftpgo-web -n sftpgo
```

เข้าถึง web interface ผ่าน:

```
http://<EXTERNAL-IP>
```

เข้าสู่ระบบด้วยข้อมูล admin ที่คุณตั้งไว้ใน secrets

### 4. ทดสอบการเชื่อมต่อ SFTP

```bash
# รับ SFTP external IP
SFTP_IP=$(kubectl get service sftpgo-sftp -n sftpgo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# ทดสอบการเชื่อมต่อ
sftp -P 22 admin@$SFTP_IP
```

---

## การตั้งค่า GitLab CI/CD

### 1. เพิ่มตัวแปรใน GitLab

ในโปรเจค GitLab ของคุณ ไปที่ **Settings > CI/CD > Variables** และเพิ่ม:

| ตัวแปร | ค่า | Protected | Masked |
|--------|-----|-----------|--------|
| `GCP_PROJECT_ID` | project-id ของคุณ | ✓ | ✗ |
| `GCP_REGION` | asia-southeast1 | ✗ | ✗ |
| `GKE_CLUSTER_NAME` | ชื่อ cluster ของคุณ | ✗ | ✗ |
| `GKE_ZONE` | asia-southeast1-a | ✗ | ✗ |
| `GCP_SERVICE_KEY` | service account key ที่ encode เป็น Base64 | ✓ | ✓ |

### 2. สร้าง Service Account สำหรับ GitLab

```bash
# สร้าง service account
gcloud iam service-accounts create gitlab-ci \
  --display-name="GitLab CI/CD Service Account"

# กำหนด roles ที่จำเป็น
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:gitlab-ci@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:gitlab-ci@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

# สร้าง key
gcloud iam service-accounts keys create gitlab-ci-key.json \
  --iam-account=gitlab-ci@$GCP_PROJECT_ID.iam.gserviceaccount.com

# Encode เป็น Base64 สำหรับ GitLab
cat gitlab-ci-key.json | base64 -w 0
```

คัดลอก output และเพิ่มเป็นตัวแปร `GCP_SERVICE_KEY` ใน GitLab

### 3. Push ไปยัง GitLab

```bash
git add .
git commit -m "Initial SFTPGo GKE deployment"
git push origin main
```

### 4. เรียกใช้ Pipeline

Pipeline จะทำงานอัตโนมัติ คุณยังสามารถ:

- ไปที่ **CI/CD > Pipelines**
- คลิก **Run Pipeline**
- เลือก deployment job ที่ต้องการรัน

---

## การสำรองและกู้คืนข้อมูล

### การสำรองข้อมูลแบบ Manual

#### ใช้ kubectl

```bash
# รับข้อมูลจาก secrets
export POSTGRES_HOST=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_HOST}' | base64 -d)
export POSTGRES_PORT=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_PORT}' | base64 -d)
export POSTGRES_DB=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
export POSTGRES_USER=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
export POSTGRES_PASSWORD=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
export GCS_BUCKET=$(kubectl get configmap sftpgo-config -n sftpgo -o jsonpath='{.data.GCS_BUCKET_NAME}')
export RETENTION_DAYS=$(kubectl get configmap sftpgo-config -n sftpgo -o jsonpath='{.data.BACKUP_RETENTION_DAYS}')
export NAMESPACE=sftpgo

# รันการสำรองข้อมูล
./scripts/backup.sh
```

#### ใช้ GitLab CI/CD

- ไปที่ **CI/CD > Pipelines**
- คลิก **Run Pipeline**
- รัน job `backup:manual`

### การกู้คืนจากข้อมูลสำรอง

#### แสดงรายการข้อมูลสำรองที่มี

```bash
gsutil ls gs://sftpgo-backups-$GCP_PROJECT_ID/backups/
```

#### กู้คืนข้อมูล

```bash
# ตั้งค่าไฟล์สำรอง
export BACKUP_FILE="gs://sftpgo-backups-project/backups/2024-01-15/sftpgo-backup-20240115_120000.tar.gz"

# รับข้อมูลการเชื่อมต่อ
export POSTGRES_HOST=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_HOST}' | base64 -d)
export POSTGRES_PORT=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_PORT}' | base64 -d)
export POSTGRES_DB=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_DB}' | base64 -d)
export POSTGRES_USER=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)
export POSTGRES_PASSWORD=$(kubectl get secret sftpgo-secrets -n sftpgo -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
export NAMESPACE=sftpgo

# รันการกู้คืน
./scripts/restore.sh $BACKUP_FILE
```

**คำเตือน**: การกระทำนี้จะเขียนทับข้อมูลที่มีอยู่!

### การสำรองข้อมูลอัตโนมัติรายวัน

ข้อมูลจะถูกสำรองอัตโนมัติทุกวันเวลา 2:00 น. UTC ผ่าน CronJob

ตรวจสอบประวัติ backup job:

```bash
kubectl get jobs -n sftpgo
```

ดู logs ของ backup job:

```bash
kubectl logs -n sftpgo job/sftpgo-backup-<job-id>
```

---

## การแก้ไขปัญหา

### Pods ไม่เริ่มทำงาน

ตรวจสอบสถานะ pod:

```bash
kubectl describe pod <pod-name> -n sftpgo
```

ปัญหาที่พบบ่อย:
- PVC ไม่ได้ bind: ตรวจสอบว่า PVC ถูกสร้างและ bound แล้ว
- Image pull errors: ตรวจสอบชื่อ image และการเข้าถึง registry
- Secrets not found: ตรวจสอบว่า secrets ถูกสร้างใน namespace ที่ถูกต้อง

### ปัญหาการเชื่อมต่อฐานข้อมูล

ตรวจสอบ logs:

```bash
kubectl logs -n sftpgo <pod-name>
```

ตรวจสอบการเชื่อมต่อฐานข้อมูลจาก pod:

```bash
kubectl exec -it -n sftpgo <pod-name> -- /bin/sh
# ข้างใน pod
nc -zv <postgres-host> 5432
```

### External IP ไม่ถูกกำหนด

ตรวจสอบ service:

```bash
kubectl describe service sftpgo-sftp -n sftpgo
```

ตรวจสอบ:
- Load balancer กำลังถูกสร้าง
- Static IP ไม่ได้ถูกใช้งานอยู่แล้ว
- Region ตรงกับ cluster region

### Backup Job ล้มเหลว

ตรวจสอบ CronJob:

```bash
kubectl get cronjob -n sftpgo
kubectl get jobs -n sftpgo
```

ดู logs:

```bash
# รับ backup job ล่าสุด
JOB_NAME=$(kubectl get jobs -n sftpgo -l app=sftpgo-backup --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

# ดู logs
kubectl logs -n sftpgo job/$JOB_NAME
```

ปัญหาที่พบบ่อย:
- GCS credentials ไม่ถูกต้อง
- การเชื่อมต่อ PostgreSQL ล้มเหลว
- สิทธิ์ไม่เพียงพอ

### ดู Events ทั้งหมด

```bash
kubectl get events -n sftpgo --sort-by='.lastTimestamp'
```

---

## ขั้นตอนถัดไป

1. **ตั้งค่า DNS**: ชี้โดเมนของคุณไปที่ static IP
2. **ตั้งค่า SSL/TLS**: กำหนดใบรับรองสำหรับการเชื่อมต่อที่ปลอดภัย
3. **กำหนดผู้ใช้**: สร้างผู้ใช้ SFTP ผ่าน web interface
4. **ตรวจสอบทรัพยากร**: ตั้งค่าการตรวจสอบและแจ้งเตือน
5. **ทดสอบการสำรองข้อมูล**: ตรวจสอบกระบวนการสำรองและกู้คืน
6. **เพิ่มความปลอดภัย**: ตรวจสอบและใช้แนวทางปฏิบัติที่ดีด้านความปลอดภัย

---

## แหล่งข้อมูลเพิ่มเติม

- [เอกสาร SFTPGo อย่างเป็นทางการ](https://github.com/drakkan/sftpgo/blob/main/docs/README.md)
- [เอกสาร GKE](https://cloud.google.com/kubernetes-engine/docs)
- [เอกสาร Cloud SQL](https://cloud.google.com/sql/docs)
- [FAQ (ภาษาอังกฤษ)](FAQ_EN.md)
- [FAQ (ภาษาไทย)](FAQ_TH.md)

---

## การสนับสนุน

สำหรับปัญหาและคำถาม:
- ตรวจสอบ [FAQ](FAQ_TH.md)
- ตรวจสอบเอกสาร SFTPGo
- ตรวจสอบ events และ logs ของ Kubernetes
- ติดต่อผู้ดูแลระบบของคุณ
