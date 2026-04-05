packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

source "googlecompute" "zephyr-runner" {
  project_id          = var.project_id
  zone                = var.zone
  source_image_family = "ubuntu-2204-lts"
  image_name          = "zephyr-runner-{{timestamp}}"
  image_family        = "zephyr-runner"
  image_description   = "GitHub Actions self-hosted runner for Zephyr membrowse onboarding"
  machine_type        = "c2-standard-8"
  disk_size           = 100
  disk_type           = "pd-ssd"
  ssh_username        = "packer"
}

build {
  sources = ["source.googlecompute.zephyr-runner"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/packer-scripts /tmp/runtime-scripts"]
  }

  provisioner "file" {
    source      = "scripts/"
    destination = "/tmp/packer-scripts"
  }

  provisioner "file" {
    source      = "../scripts/"
    destination = "/tmp/runtime-scripts"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/packer-scripts/*.sh",
      "sudo mkdir -p /opt/scripts",
      "sudo cp /tmp/runtime-scripts/*.sh /opt/scripts/",
      "sudo chmod +x /opt/scripts/*.sh",
      "rm -rf /tmp/runtime-scripts",
    ]
  }

  provisioner "shell" {
    script          = "scripts/provision.sh"
    execute_command = "sudo bash -c '{{ .Path }}'"
  }
}
