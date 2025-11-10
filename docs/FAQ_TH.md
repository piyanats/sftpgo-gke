# SFTPGo บน GKE - คำถามที่พบบ่อย (FAQ)

## สารบัญ

- [คำถามทั่วไป](#คำถามทั่วไป)
- [การติดตั้งและตั้งค่า](#การติดตั้งและตั้งค่า)
- [ฐานข้อมูล](#ฐานข้อมูล)
- [เครือข่ายและ Load Balancer](#เครือข่ายและ-load-balancer)
- [พื้นที่จัดเก็บข้อมูล](#พื้นที่จัดเก็บข้อมูล)
- [การสำรองและกู้คืนข้อมูล](#การสำรองและกู้คืนข้อมูล)
- [ความปลอดภัย](#ความปลอดภัย)
- [ประสิทธิภาพและการปรับขนาด](#ประสิทธิภาพและการปรับขนาด)
- [การแก้ไขปัญหา](#การแก้ไขปัญหา)
- [CI/CD](#cicd)

---

## คำถามทั่วไป

### ถาม: SFTPGo คืออะไร?

**ตอบ:** SFTPGo เป็นเซิร์ฟเวอร์ SFTP ที่มีฟีเจอร์ครบครันและปรับแต่งได้สูง รองรับ HTTP/S สามารถให้บริการได้ทั้ง local filesystem, S3 (AWS หรือที่เข้ากันได้) และ Google Cloud Storage มี web-based admin interface และรองรับการยืนยันตัวตนหลายแบบ

### ถาม: ทำไมต้องติดตั้ง SFTPGo บน GKE?

**ตอบ:** การติดตั้งบน GKE ให้ประโยชน์:
- ความพร้อมใช้งานสูงผ่านการมี replica หลายตัว
- ความสามารถในการปรับขนาดอัตโนมัติ
- การสำรองและกู้คืนภัยพิบัติที่ง่าย
- การเชื่อมต่อกับบริการ Google Cloud
- โครงสร้างพื้นฐานระดับมืออาชีพ
- การจัดการที่ง่ายผ่าน Kubernetes

### ถาม: มีค่าใช้จ่ายอะไรบ้าง?

**ตอบ:** ค่าใช้จ่ายหลักประกอบด้วย:
- GKE cluster (nodes)
- Persistent storage (GCE disks)
- Load balancer (external IP)
- Cloud SQL for PostgreSQL (ถ้าใช้)
- GCS สำหรับสำรองข้อมูล
- Network egress

ประมาณการค่าใช้จ่ายโดยใช้ [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator)

### ถาม: สามารถใช้งานในระบบ production ได้หรือไม่?

**ตอบ:** ได้ การตั้งค่านี้ออกแบบมาสำหรับการใช้งาน production พร้อม:
- ความพร้อมใช้งานสูง (replica หลายตัว)
- การสำรองข้อมูลอัตโนมัติ
- ฐานข้อมูล PostgreSQL ภายนอก
- พื้นที่จัดเก็บแบบ persistent
- การกระจายโหลด

อย่างไรก็ตาม ควรทดสอบอย่างละเอียดใน staging environment ก่อน

---

## การติดตั้งและตั้งค่า

### ถาม: ข้อกำหนดขั้นต่ำคืออะไร?

**ตอบ:**
- GKE cluster ที่มี node อย่างน้อย 2 ตัว (n1-standard-2 หรือดีกว่า)
- ฐานข้อมูล PostgreSQL ภายนอก (Cloud SQL หรือติดตั้งเอง)
- GCS bucket สำหรับสำรองข้อมูล
- Static IP address
- ความรู้พื้นฐานเกี่ยวกับ Kubernetes และ GCP

### ถาม: ใช้เวลาติดตั้งนานแค่ไหน?

**ตอบ:**
- การตั้งค่าเริ่มต้น: 30-60 นาที
- การ deploy: 5-10 นาที
- รวม: ประมาณ 1-2 ชั่วโมงสำหรับการตั้งค่าครั้งแรก

### ถาม: จำเป็นต้องใช้ Cloud SQL หรือสามารถใช้ PostgreSQL ของตัวเองได้?

**ตอบ:** สามารถใช้ได้ทั้งสองแบบ:
- **Cloud SQL**: จัดการอัตโนมัติ, สำรองข้อมูลอัตโนมัติ, ติดตั้งง่าย
- **PostgreSQL ติดตั้งเอง**: ควบคุมได้มากขึ้น, ค่าใช้จ่ายอาจต่ำกว่า
- **PostgreSQL แบบ managed อื่นๆ**: AWS RDS, Azure Database ฯลฯ (ต้องเข้าถึงได้จาก GKE)

### ถาม: สามารถติดตั้งโดยไม่ใช้ GitLab CI/CD ได้หรือไม่?

**ตอบ:** ได้! GitLab CI/CD pipeline เป็นตัวเลือก คุณสามารถ deploy ด้วยตนเองใช้คำสั่ง `kubectl` ตามที่แสดงในคู่มือการติดตั้ง

### ถาม: ต้องใช้ Kubernetes เวอร์ชันอะไร?

**ตอบ:** ต้องใช้ Kubernetes 1.25 ขึ้นไป เวอร์ชันนี้รองรับฟีเจอร์ `timeZone` ของ CronJob ที่ใช้ในกำหนดการสำรองข้อมูล manifests ใช้ API เวอร์ชันที่เสถียรซึ่งทำงานได้กับ Kubernetes รุ่นล่าสุด

---

## ฐานข้อมูล

### ถาม: ทำไมต้องใช้ฐานข้อมูล PostgreSQL ภายนอกแทนการรันใน Kubernetes?

**ตอบ:** ฐานข้อมูลภายนอก (เช่น Cloud SQL) ให้ประโยชน์:
- การสำรองข้อมูลอัตโนมัติ
- ความพร้อมใช้งานสูง
- การอัปเดตและแพตช์อัตโนมัติ
- ประสิทธิภาพที่ดีขึ้น
- การกู้คืนภัยพิบัติที่ง่ายขึ้น
- การแยกความกังวล

### ถาม: สามารถใช้ MySQL แทน PostgreSQL ได้หรือไม่?

**ตอบ:** ได้ SFTPGo รองรับฐานข้อมูลหลายแบบ:
- PostgreSQL (แนะนำ)
- MySQL/MariaDB
- SQLite (ไม่แนะนำสำหรับ production)
- CockroachDB

อัปเดต `SFTPGO_DATA_PROVIDER__DRIVER` ใน ConfigMap ตามนั้น

### ถาม: จะย้ายข้อมูลจาก SQLite ไป PostgreSQL ได้อย่างไร?

**ตอบ:** SFTPGo มีเครื่องมือสำหรับการย้ายข้อมูล ตรวจสอบ[เอกสารอย่างเป็นทางการ](https://github.com/drakkan/sftpgo/blob/main/docs/db-migration.md) สำหรับขั้นตอนการย้ายฐานข้อมูล

### ถาม: ถ้าการเชื่อมต่อฐานข้อมูลล้มเหลวจะทำอย่างไร?

**ตอบ:** ตรวจสอบ:
1. ข้อมูล database credentials ใน secrets ถูกต้อง
2. ฐานข้อมูลเข้าถึงได้จาก GKE cluster (firewall rules)
3. ฐานข้อมูลกำลังทำงานและรับการเชื่อมต่อ
4. ตรวจสอบ pod logs: `kubectl logs -n sftpgo <pod-name>`

---

## เครือข่ายและ Load Balancer

### ถาม: ทำไมต้องใช้ static IP?

**ตอบ:** Static IP ให้ประโยชน์:
- จุดเชื่อมต่อที่คงที่สำหรับผู้ใช้
- การตั้งค่า DNS ที่ง่ายขึ้น
- จำเป็นสำหรับ firewall rules บางอย่าง
- ดีกว่าสำหรับสภาพแวดล้อม production

### ถาม: Static IP มีค่าใช้จ่ายเท่าไหร่?

**ตอบ:** Google Cloud คิดค่าใช้จ่าย:
- IP ที่จองแต่ไม่ได้ใช้: ~$3-4/เดือน
- IP ที่ใช้งาน: ฟรี (จ่ายเฉพาะ egress traffic)

### ถาม: สามารถใช้ Ingress แทน LoadBalancer ได้หรือไม่?

**ตอบ:** สำหรับ HTTP ได้ สำหรับ SFTP ต้องใช้ LoadBalancer (Layer 4) เพราะ Ingress รองรับเฉพาะ HTTP/HTTPS (Layer 7)

คุณสามารถใช้ทั้งสอง:
- LoadBalancer สำหรับ SFTP
- Ingress สำหรับ HTTP พร้อม SSL termination

### ถาม: จะตั้งค่า SSL/TLS ได้อย่างไร?

**ตอบ:** ตัวเลือก:
1. **สำหรับ HTTP**: ใช้ Ingress กับ cert-manager สำหรับ Let's Encrypt certificates อัตโนมัติ
2. **สำหรับ SFTP**: กำหนดค่า SFTPGo ให้ใช้ certificates (mount certificates เป็น secrets)

### ถาม: มี port อะไรบ้างที่เปิดใช้งาน?

**ตอบ:**
- Port 22 (2022 ภายใน): SFTP
- Port 80 (8080 ภายใน): Web UI & API

---

## พื้นที่จัดเก็บข้อมูล

### ถาม: ต้องการพื้นที่จัดเก็บเท่าไหร่?

**ตอบ:** ขึ้นอยู่กับการใช้งาน:
- **sftpgo-data** (ค่าเริ่มต้น 100GB): การกำหนดค่าและ metadata ของ SFTPGo
- **sftpgo-home** (ค่าเริ่มต้น 500GB): ไฟล์ของผู้ใช้

ปรับตามความต้องการ เริ่มเล็กแล้วปรับขนาดทีหลังได้

### ถาม: สามารถใช้ storage class ที่แตกต่างกันได้หรือไม่?

**ตอบ:** ได้! GKE storage classes ที่มี:
- `standard-rwo`: Standard persistent disks (ค่าเริ่มต้น)
- `premium-rwo`: SSD persistent disks (เร็วกว่า, แพงกว่า)
- `standard`: รุ่นเก่า, ไม่แนะนำ

อัปเดต `storageClassName` ใน `k8s/persistent-volume-claim.yaml`

### ถาม: จะปรับขนาด persistent volume ได้อย่างไร?

**ตอบ:**
1. แก้ไข PVC: `kubectl edit pvc sftpgo-data -n sftpgo`
2. อัปเดตขนาด storage
3. รีสตาร์ท pod

หมายเหตุ: เพิ่มขนาดได้เท่านั้น ลดไม่ได้ storage class ต้องรองรับ volume expansion

### ถาม: สามารถใช้ Google Cloud Storage (GCS) เป็น storage backend ได้หรือไม่?

**ตอบ:** ได้! SFTPGo รองรับ GCS เป็น storage backend กำหนดค่าใน SFTPGo settings นี่แตกต่างจาก persistent volumes ที่ใช้สำหรับ SFTPGo เอง

---

## การสำรองและกู้คืนข้อมูล

### ถาม: มีอะไรที่ถูกสำรองบ้าง?

**ตอบ:** สคริปต์สำรองข้อมูลจะสำรอง:
1. ฐานข้อมูล PostgreSQL (dump ทั้งหมด)
2. ไดเรกทอรีข้อมูล SFTPGo (`/srv/sftpgo`)
3. ไดเรกทอรี home ของ SFTPGo (`/var/lib/sftpgo`)
4. ไฟล์ metadata พร้อมข้อมูลการสำรอง

### ถาม: ข้อมูลสำรองถูกเก็บที่ไหน?

**ตอบ:** ข้อมูลสำรองถูกเก็บใน Google Cloud Storage (GCS) ใน bucket ที่คุณระบุ โครงสร้าง:
```
gs://your-bucket/backups/
  ├── 2024-01-15/
  │   └── sftpgo-backup-20240115_020000.tar.gz
  ├── 2024-01-16/
  │   └── sftpgo-backup-20240116_020000.tar.gz
  └── ...
```

### ถาม: ข้อมูลสำรองถูกเก็บไว้นานแค่ไหน?

**ตอบ:** ค่าเริ่มต้น: 30 วัน กำหนดค่า `BACKUP_RETENTION_DAYS` ใน `k8s/configmap.yaml`

### ถาม: สามารถสำรองข้อมูลด้วยตนเองได้หรือไม่?

**ตอบ:** ได้! สองวิธี:
1. **Local**: รัน `./scripts/backup.sh` พร้อมตัวแปรสภาพแวดล้อมที่ถูกต้อง
2. **GitLab CI/CD**: เรียกใช้ job `backup:manual`

### ถาม: จะกู้คืนจากข้อมูลสำรองได้อย่างไร?

**ตอบ:**
```bash
./scripts/restore.sh gs://bucket/path/to/backup.tar.gz
```

ทำตามคำแนะนำ สามารถกู้คืน:
- เฉพาะฐานข้อมูล: `--db-only`
- เฉพาะข้อมูล: `--data-only`
- ทั้งหมด (ค่าเริ่มต้น)

### ถาม: เกิดอะไรขึ้นระหว่างการกู้คืน?

**ตอบ:**
1. ดาวน์โหลดข้อมูลสำรองจาก GCS
2. สำหรับฐานข้อมูล: ลบและสร้างฐานข้อมูลใหม่ แล้วกู้คืนข้อมูล
3. สำหรับไฟล์: แทนที่ไดเรกทอรีข้อมูล SFTPGo
4. SFTPGo pods ถูกรีสตาร์ท

**คำเตือน**: การกระทำนี้จะเขียนทับข้อมูลที่มีอยู่!

### ถาม: จะทดสอบข้อมูลสำรองได้อย่างไร?

**ตอบ:** แนวทางปฏิบัติที่ดี:
1. สร้าง GKE cluster แยกสำหรับทดสอบ
2. รันการกู้คืนบน test cluster
3. ตรวจสอบความถูกต้องของข้อมูล
4. ทดสอบการเชื่อมต่อ SFTP และการเข้าถึงไฟล์

---

## ความปลอดภัย

### ถาม: จะรักษาความปลอดภัย admin interface ได้อย่างไร?

**ตอบ:**
1. ใช้รหัสผ่านที่แข็งแรงใน secrets
2. ตั้งค่า Ingress พร้อม SSL/TLS
3. จำกัดการเข้าถึงด้วย firewall rules
4. เปิด 2FA ใน SFTPGo settings
5. ใช้การยืนยันตัวตน OAuth2 หรือ OIDC

### ถาม: จัดการ secrets อย่างไร?

**ตอบ:**
- เก็บใน Kubernetes Secrets
- เข้ารหัส Base64 (ไม่ได้เข้ารหัสตามค่าเริ่มต้น)
- สำหรับ production: ใช้ GCP Secret Manager หรือ Sealed Secrets
- อย่า commit secrets ลง git

### ถาม: ควรเข้ารหัส persistent volumes หรือไม่?

**ตอบ:** ใช่ สำหรับ production:
1. GKE เข้ารหัส data at rest ตามค่าเริ่มต้น
2. สำหรับความปลอดภัยเพิ่มเติม ใช้ customer-managed encryption keys (CMEK)
3. กำหนดค่าใน GCP console หรือผ่าน Terraform

### ถาม: จะหมุนเวียน credentials ได้อย่างไร?

**ตอบ:**
1. อัปเดต secrets: `kubectl edit secret sftpgo-secrets -n sftpgo`
2. รีสตาร์ท pods: `kubectl rollout restart deployment/sftpgo -n sftpgo`

สำหรับการหมุนเวียนรหัสผ่านฐานข้อมูล อัปเดตทั้ง secret และฐานข้อมูล

### ถาม: การรับส่งข้อมูลผ่านเครือข่ายถูกเข้ารหัสหรือไม่?

**ตอบ:**
- **SFTP**: เข้ารหัสตามค่าเริ่มต้น
- **HTTP**: ใช้ Ingress พร้อม TLS สำหรับ web interface

---

## ประสิทธิภาพและการปรับขนาด

### ถาม: จะปรับขนาด SFTPGo ได้อย่างไร?

**ตอบ:** อัปเดต replicas:
```bash
kubectl scale deployment/sftpgo --replicas=3 -n sftpgo
```

หรือแก้ไข `k8s/deployment.yaml` และ apply

### ถาม: มีความต้องการทรัพยากรเท่าไหร่?

**ตอบ:** ค่าเริ่มต้น (ต่อ pod):
- **Requests**: 500m CPU, 512Mi memory
- **Limits**: 2000m CPU, 2Gi memory

ปรับตามปริมาณงานใน `k8s/deployment.yaml`

### ถาม: SFTPGo สามารถ auto-scale ได้หรือไม่?

**ตอบ:** ได้! สร้าง HorizontalPodAutoscaler:
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

### ถาม: รองรับผู้ใช้พร้อมกันได้กี่คน?

**ตอบ:** ขึ้นอยู่กับ:
- ทรัพยากรของ node
- จำนวน replicas
- ประสิทธิภาพฐานข้อมูล
- แบนด์วิธเครือข่าย
- Storage I/O

ด้วยการตั้งค่าเริ่มต้น (2 replicas, n1-standard-2): ~100-200 ผู้ใช้พร้อมกัน ปรับเพิ่มสำหรับมากขึ้น

---

## การแก้ไขปัญหา

### ถาม: Pods อยู่ในสถานะ CrashLoopBackOff

**ตอบ:** สาเหตุที่พบบ่อย:
1. การเชื่อมต่อฐานข้อมูลล้มเหลว - ตรวจสอบ credentials และการเชื่อมต่อ
2. การกำหนดค่าไม่ถูกต้อง - ตรวจสอบ ConfigMap และ Secrets
3. ขาด dependencies - ตรวจสอบ pod logs
4. ทรัพยากรจำกัด - ตรวจสอบทรัพยากร node

Debug: `kubectl describe pod <pod-name> -n sftpgo`

### ถาม: External IP แสดง <pending>

**ตอบ:**
- ปกติใช้เวลา 2-5 นาทีในการจัดสรร
- ตรวจสอบ: `kubectl describe service sftpgo-sftp -n sftpgo`
- ยืนยัน static IP ไม่ได้ถูกใช้งานอยู่แล้ว
- ตรวจสอบ quotas ไม่เกิน

### ถาม: เชื่อมต่อ SFTP ไม่ได้

**ตอบ:** ตรวจสอบ:
1. External IP ถูกกำหนดแล้ว: `kubectl get svc -n sftpgo`
2. Firewall rules อนุญาต port 22
3. ข้อมูลผู้ใช้ถูกต้อง
4. Pods กำลังทำงาน: `kubectl get pods -n sftpgo`

### ถาม: Backup job ล้มเหลว

**ตอบ:** ปัญหาที่พบบ่อย:
1. GCS credentials ไม่ถูกต้อง - ตรวจสอบ secret
2. การเชื่อมต่อฐานข้อมูลล้มเหลว - ตรวจสอบ credentials
3. ไม่มี pods - ตรวจสอบว่า deployment กำลังทำงาน
4. สิทธิ์ไม่เพียงพอ - ตรวจสอบ service account roles

ดู logs: `kubectl logs -n sftpgo job/<job-name>`

### ถาม: การใช้ memory สูง

**ตอบ:**
- ปกติสำหรับการถ่ายโอนไฟล์
- เพิ่ม limits ถ้า pods ถูก OOMKilled
- ตรวจหา memory leaks ใน logs
- พิจารณา vertical หรือ horizontal scaling

---

## CI/CD

### ถาม: รองรับระบบ CI/CD อะไรบ้าง?

**ตอบ:** repository มี GitLab CI/CD แต่สามารถดัดแปลงสำหรับ:
- GitHub Actions
- Jenkins
- CircleCI
- Cloud Build
- CI/CD ใดๆ ที่มี kubectl และ gcloud

### ถาม: จำเป็นต้องใช้ CI/CD หรือไม่?

**ตอบ:** ไม่ เป็นตัวเลือก สามารถ deploy ด้วยตนเองใช้คำสั่ง kubectl

### ถาม: จะปรับแต่ง pipeline ได้อย่างไร?

**ตอบ:** แก้ไข `.gitlab-ci.yml`:
- เพิ่ม/ลบ stages
- แก้ไข deployment logic
- เพิ่มขั้นตอนการทดสอบ
- กำหนดค่าการแจ้งเตือน

### ถาม: สามารถ deploy ไปยังหลาย environment ได้หรือไม่?

**ตอบ:** ได้! pipeline มี:
- `deploy:dev` สำหรับ development
- `deploy:prod` สำหรับ production

ปรับแต่งสำหรับ staging, testing ฯลฯ

### ถาม: จะ rollback deployment ได้อย่างไร?

**ตอบ:**
```bash
kubectl rollout undo deployment/sftpgo -n sftpgo
```

หรือกู้คืนจากข้อมูลสำรองก่อนหน้า

---

## มีคำถามเพิ่มเติม?

ถ้าคำถามของคุณไม่ได้รับคำตอบที่นี่:

1. ตรวจสอบ [คู่มือการติดตั้ง](INSTALLATION_TH.md)
2. ตรวจสอบ [เอกสาร SFTPGo](https://github.com/drakkan/sftpgo/blob/main/docs/README.md)
3. ตรวจสอบเอกสาร Kubernetes และ GKE
4. ตรวจสอบ logs: `kubectl logs -n sftpgo <pod-name>`
5. ตรวจสอบ events: `kubectl get events -n sftpgo`

---

**อัปเดตล่าสุด**: 2024
**เวอร์ชัน**: 1.0
