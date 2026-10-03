output "public_ip" {
  description = "Ephemeral public IP on the instance VNIC. It changes if the VNIC is recreated. This is not a reserved public IP."
  value       = oci_core_instance.nanoclaw.public_ip
}

output "instance_id" {
  description = "OCID of the Ampere A1 instance."
  value       = oci_core_instance.nanoclaw.id
}

output "ssh_command" {
  description = "SSH command for the Ubuntu image default user."
  value       = "ssh -i <private-key> ubuntu@${oci_core_instance.nanoclaw.public_ip}"
}
