variable "tenancy_ocid" {
  description = "OCI tenancy OCID (oci iam tenancy get / console tenancy page)."
  type        = string
}

variable "user_ocid" {
  description = "OCI API user OCID. Use a dedicated user, not the tenancy admin, when you can."
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint of the API public key uploaded to that user."
  type        = string
}

variable "private_key_path" {
  description = "Absolute path to the API private key PEM on the machine running Terraform. Never commit this file."
  type        = string
}

variable "region" {
  description = "OCI region identifier, for example us-ashburn-1. Ampere A1 capacity is regional; pick a home region that still has Always Free A1."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment OCID. The tenancy root compartment OCID is valid for Always Free."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Absolute path to the SSH public key installed for the ubuntu user."
  type        = string
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to reach SSH (tcp/22). Narrow this to your IP. Ingress is free; this is exposure, not billing."
  type        = string
  default     = "0.0.0.0/0"
}

variable "availability_domain_index" {
  description = "Index into the tenancy availability domain list. A1 capacity is often only in one AD; change this if launch fails with out-of-host-capacity."
  type        = number
  default     = 0
}

variable "instance_name" {
  description = "Display name of the compute instance."
  type        = string
  default     = "nanoclaw"
}
