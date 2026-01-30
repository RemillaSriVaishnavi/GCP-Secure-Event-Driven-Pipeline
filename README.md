# Secure Event-Driven Data Processing Pipeline on Google Cloud

## 📌 Project Overview

This project implements a **secure, private, event-driven data processing pipeline** on **Google Cloud Platform (GCP)** using **Terraform**.

The system automatically processes file upload events from **Google Cloud Storage (GCS)**, publishes them to **Pub/Sub**, triggers a **Cloud Function**, and stores metadata in a **private Cloud SQL (PostgreSQL)** database.

The entire infrastructure is provisioned using **Infrastructure as Code (IaC)** and follows **production-grade security best practices**, including private networking, least-privilege IAM, and secret management.


## 🎯 Problem Statement

In real-world cloud environments, organizations require:

- Event-driven processing
- Secure, private access to databases
- No public IP exposure
- No hardcoded credentials
- Automated infrastructure provisioning

This project demonstrates how to design and implement such a system using **GCP-native services** while maintaining **security, scalability, and auditability**.


## 🏗️ Architecture Overview

### High-Level Flow

1. A file is uploaded to a **GCS bucket**
2. GCS sends an `OBJECT_FINALIZE` event to **Pub/Sub**
3. **Cloud Function** is triggered by Pub/Sub
4. Cloud Function:
   - Runs with a dedicated IAM service account
   - Fetches DB credentials from **Secret Manager**
   - Connects to **Cloud SQL via private IP**
5. File metadata is stored in the `events` table

### Key Architectural Decisions

- **Custom VPC** with no public subnets
- **Cloud SQL private IP only**
- **Serverless VPC Access Connector** for Cloud Function
- **Cloud NAT** for outbound access
- **Secret Manager** for credentials
- **Terraform-only provisioning**


## 🔐 Security Design

- No public IPs on Cloud SQL
- No hardcoded secrets
- Least-privilege IAM roles
- Private service networking
- Billing-enabled but controlled resource usage


## 🧩 Services Used

| Service | Purpose |
|------|------|
| VPC | Private network |
| Cloud NAT | Outbound internet for private resources |
| Serverless VPC Connector | Connect Cloud Functions to VPC |
| Cloud Storage | Event source |
| Pub/Sub | Event transport |
| Cloud Functions | Event processing |
| Cloud SQL (PostgreSQL 13) | Persistent storage |
| Secret Manager | Secure password storage |
| IAM | Identity & access control |
| Terraform | Infrastructure provisioning |


## 📁 Repository Structure

```
.
├── provider.tf
├── main.tf
├── variables.tf
├── outputs.tf
├── archive.tf
├── function/
│   ├── main.py
│   └── requirements.txt
└── README.md

```

## ⚙️ Prerequisites

- Google Cloud account with **billing enabled**
- Project where you have **Owner** role
- Installed tools:
  - `terraform`
  - `gcloud`
  - `gsutil`


## 🚀 Deployment Steps

### 1️⃣ Authenticate with Google Cloud

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <YOUR_PROJECT_ID>
````


### 2️⃣ Initialize Terraform

```bash
terraform init
```


### 3️⃣ Validate Configuration

```bash
terraform validate
```


### 4️⃣ Review Execution Plan

```bash
terraform plan
```


### 5️⃣ Apply Infrastructure

```bash
terraform apply
```


## 🧪 End-to-End Verification

### Upload a Test File

```bash
echo "test" > test.txt
```


### Verify Cloud Function Logs

```bash
gcloud functions logs read event-processing-function --region=us-central1
```

Expected output:

```
Processing file 'test.txt'
Successfully recorded event
```

### Verify Database Entry

```bash
gcloud sql connect event-db-instance --user=event_user
```

Inside PostgreSQL:

```sql
\c events_db;
SELECT * FROM events;
```

## 🏁 Conclusion

This project demonstrates a **real-world, production-grade cloud architecture** using Google Cloud Platform and Terraform. It highlights best practices in security, automation, and event-driven system design.
