terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  ad = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name

  # Always Free shape: 2 OCPU and 12 GB is 1,488 OCPU-hours and 8,928 GB-hours
  # in a 31-day month, under the 1,500 / 9,000 ceiling requested here and under
  # Oracle's published A1 allowance (3,000 OCPU-hours and 18,000 GB-hours).
  ocpus          = 2
  memory_in_gbs  = 12
  boot_volume_gb = 50

  # The VM only needs git and curl so the two repos can be cloned.
  # Node, pnpm, and Docker are installed by nanoclaw.sh (setup/install-node.sh
  # and setup/install-docker.sh). Do not install them here.
  cloud_init = <<-EOT
    #cloud-config
    package_update: true
    packages:
      - ca-certificates
      - curl
      - git
      - iptables-persistent
    runcmd:
      # OCI Ubuntu images reject new SSH in iptables. Leave the security list
      # as the firewall so the installer can be reached.
      - [bash, -c, "iptables -P INPUT ACCEPT; iptables -P FORWARD ACCEPT; iptables -P OUTPUT ACCEPT; iptables -F; iptables -t nat -F || true; netfilter-persistent save || true"]
  EOT
}

resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "${var.instance_name}-vcn"
  dns_label      = "nanoclaw"
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.instance_name}-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.instance_name}-public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.instance_name}-public-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  ingress_security_rules {
    protocol  = "6"
    source    = var.ssh_ingress_cidr
    stateless = false

    tcp_options {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "${var.instance_name}-public"
  dns_label                  = "public"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
  prohibit_internet_ingress  = false
}

resource "oci_core_instance" "nanoclaw" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.ad
  display_name        = var.instance_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = local.ocpus
    memory_in_gbs = local.memory_in_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = local.boot_volume_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    display_name     = "${var.instance_name}-vnic"
    hostname_label   = var.instance_name
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data           = base64encode(local.cloud_init)
  }

  # No oci_core_public_ip, no load balancer, no extra volume, no object storage.
  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}
