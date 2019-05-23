provider "google" {
  region = "${var.GCP_Region}"
  credentials = "${file(${var.credentials_file})}"
}

provider "random" {}