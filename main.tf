# 1. Custom VPC

resource "google_compute_network" "event_vpc" {
  name                    = "event-processing-vpc"
  auto_create_subnetworks = false
}


# 2. Private Subnet

resource "google_compute_subnetwork" "private_subnet" {
  name          = "private-subnet-services"
  ip_cidr_range = "10.10.10.0/24"
  region        = var.gcp_region
  network       = google_compute_network.event_vpc.id
}


# 3. Firewall Rule (Postgres access)

resource "google_compute_firewall" "allow_internal_postgres" {
  name    = "allow-internal-postgres"
  network = google_compute_network.event_vpc.name

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  # This will later match the Serverless VPC Connector range
  source_ranges = ["10.8.0.0/28"]
}


# 4. Cloud Router

resource "google_compute_router" "nat_router" {
  name    = "nat-router"
  network = google_compute_network.event_vpc.id
  region  = var.gcp_region
}


# 5. Cloud NAT

resource "google_compute_router_nat" "cloud_nat" {
  name                               = "cloud-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}


# 6. Serverless VPC Access Connector

resource "google_vpc_access_connector" "serverless_connector" {
  name          = "serverless-connector"
  region        = var.gcp_region
  network       = google_compute_network.event_vpc.name
  ip_cidr_range = "10.8.0.0/28"
}


# 7. Enable Required APIs

resource "google_project_service" "sqladmin" {
  service = "sqladmin.googleapis.com"
}

resource "google_project_service" "servicenetworking" {
  service = "servicenetworking.googleapis.com"
}

resource "google_project_service" "secretmanager" {
  service = "secretmanager.googleapis.com"
}


# 8. Private Service Networking

resource "google_compute_global_address" "private_service_range" {
  name          = "private-service-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.event_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.event_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}


# 9. Cloud SQL - PostgreSQL (Private IP)

resource "google_sql_database_instance" "private_instance" {
  name             = "event-db-instance"
  database_version = "POSTGRES_13"
  region           = var.gcp_region

  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]

  settings {
    tier = "db-g1-small"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.event_vpc.id
    }
  }

  deletion_protection = false
}


# 10. Database

resource "google_sql_database" "events_db" {
  name     = "events_db"
  instance = google_sql_database_instance.private_instance.name
}


# 11. Secret Manager - DB Password

resource "google_secret_manager_secret" "db_password" {
  secret_id = "db-password"

  replication {
    automatic = true
  }
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}


# 12. Database User

resource "google_sql_user" "event_user" {
  name     = "event_user"
  instance = google_sql_database_instance.private_instance.name
  password = random_password.db_password.result
}


# 13. Cloud Function Service Account

resource "google_service_account" "event_function_sa" {
  account_id   = "event-function-sa"
  display_name = "Event Processing Cloud Function SA"
}



# 14. IAM Roles

resource "google_project_iam_member" "pubsub_subscriber" {
  project = var.project_id
  role   = "roles/pubsub.subscriber"
  member = "serviceAccount:${google_service_account.event_function_sa.email}"
}

resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role   = "roles/cloudsql.client"
  member = "serviceAccount:${google_service_account.event_function_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "secret_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.event_function_sa.email}"
}


# 15. Pub/Sub Topic

resource "google_pubsub_topic" "gcs_events" {
  name = "gcs-events"
}



# 16. GCS Bucket

resource "google_storage_bucket" "event_bucket" {
  name          = "${var.gcp_project_id}-event-bucket"
  location      = var.gcp_region
  force_destroy = true
}



# 17. GCS Notification to Pub/Sub

resource "google_storage_notification" "bucket_notification" {
  bucket         = google_storage_bucket.event_bucket.name
  topic          = google_pubsub_topic.gcs_events.id
  event_types    = ["OBJECT_FINALIZE"]
  payload_format = "JSON_API_V1"
}


# 18. Cloud Function

resource "google_cloudfunctions_function" "event_processor" {
  name        = "event-processing-function"
  runtime     = "python39"
  region      = var.gcp_region
  entry_point = "process_event"

  source_archive_bucket = google_storage_bucket.event_bucket.name
  source_archive_object = "function-source.zip"

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.gcs_events.name
  }

  service_account_email = google_service_account.event_function_sa.email

  vpc_connector = google_vpc_access_connector.serverless_connector.name

  environment_variables = {
    DB_USER            = google_sql_user.event_user.name
    DB_NAME            = google_sql_database.events_db.name
    DB_HOST            = google_sql_database_instance.private_instance.private_ip_address
    DB_PASSWORD_SECRET = google_secret_manager_secret.db_password.secret_id
    GCP_PROJECT        = var.gcp_project_id
  }
}
