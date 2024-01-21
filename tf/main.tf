resource "google_kms_key_ring" "terraform_state_key_ring" {
  name     = "terraform-state-key-ring"
  location = "us-central1"
}

resource "google_kms_crypto_key" "terraform_state_bucket" {
  name            = "terraform-state-crypto-key"
  key_ring        = google_kms_key_ring.terraform_state_key_ring.id
  rotation_period = "100000s"

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_project_iam_member" "default" {
  project = var.project_id
  role   = "roles/storage.admin"
  member = "user:mfreeman451@gmail.com"
}

resource "random_id" "bucket_prefix" {
  byte_length = 8
}

resource "google_storage_bucket" "default" {
  name          = "${random_id.bucket_prefix.hex}-bucket-tfstate"
  force_destroy = false
  location      = "us-central1"
  storage_class = "STANDARD"
  versioning {
    enabled = true
  }
  encryption {
    default_kms_key_name = google_kms_crypto_key.terraform_state_bucket.id
  }
  depends_on = [
    google_project_iam_member.default
  ]
}
