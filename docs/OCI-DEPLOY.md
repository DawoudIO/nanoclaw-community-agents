# Deploy NanoClaw on OCI Always Free

This path creates one Ampere A1 VM (2 OCPU, 12 GB RAM, 50 GB boot), one VCN, one public subnet, and an ephemeral public IP on that VNIC. It does not create a reserved public IP, a load balancer, an extra block volume, or an Object Storage bucket.

Terraform encodes those limits. It cannot promise Oracle will never invoice the tenancy. A charge still happens if the account is not Always Free eligible, if the home region has no free A1 quota left and a paid shape is substituted by hand, or if some other resource already exists in the tenancy. Before `apply`, the compartment should contain no compute, no reserved IPs, and no block volumes beyond what this stack creates. After `apply`, confirm the cost estimate in the console is zero and check Usage for the next day.

A1 capacity is often "out of host capacity." That error is free. Retry another availability domain (`availability_domain_index`) or another Always Free region. Do not switch the shape.

## 1. API key

In the OCI console: Profile → User settings → API keys → Add API key → Generate or paste a public key.

Or from the laptop that will run Terraform:

```bash
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
openssl rsa -pubout -outform DER -in ~/.oci/oci_api_key.pem | openssl md5 -c
```

Upload `~/.oci/oci_api_key_public.pem` on the user. Copy the tenancy OCID, user OCID, fingerprint, and region into `terraform/terraform.tfvars` (start from `terraform.tfvars.example`).

SSH key for the VM, separate from the API key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/nanoclaw_oci -N ""
```

Set `ssh_public_key_path` to `~/.ssh/nanoclaw_oci.pub`.

The API user needs manage rights on the compartment for `vcn`, `instance`, and `volume-family` (the boot volume is part of the instance). A policy limited to those resources is enough:

```
Allow group NanoclawDeploy to manage instance-family in compartment <name>
Allow group NanoclawDeploy to manage volume-family in compartment <name>
Allow group NanoclawDeploy to manage virtual-network-family in compartment <name>
Allow group NanoclawDeploy to read app-catalog-listing in tenancy
```

`volume-family` here is only so the 50 GB boot volume can be created with the instance. Do not add a `oci_core_volume` resource.

## 2. Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output public_ip
```

`plan` must show one instance of shape `VM.Standard.A1.Flex`, `ocpus = 2`, `memory_in_gbs = 12`, `boot_volume_size_in_gbs = 50`, and `assign_public_ip = true`. It must not show `oci_core_public_ip`, `oci_load_balancer`, `oci_core_volume`, or `oci_objectstorage_bucket`.

Cloud-init installs git and curl and flushes the image iptables policy so SSH matches the security list. Node, pnpm, and Docker come from `nanoclaw.sh`.

## 3. App deploy

From this repo, on the laptop:

```bash
IP=$(terraform output -raw public_ip)
./deploy.sh "$IP"
```

`deploy.sh` clones https://github.com/DawoudIO/nanoclaw and https://github.com/DawoudIO/nanoclaw-community-agents into the `ubuntu` home directory, runs `scripts/install-templates.sh`, then execs:

```bash
bash ./nanoclaw.sh --template-path opensource/community-manager
```

`--template-path` is a path under `~/nanoclaw/templates`. When that directory exists, the installer uses it and skips the "From local templates" menu. The same preset is `NANOCLAW_TEMPLATE_PATH=opensource/community-manager bash ./nanoclaw.sh`.

To run it yourself after the clones are in place:

```bash
ssh -t -i ~/.ssh/nanoclaw_oci ubuntu@"$IP"
cd ~/nanoclaw-community-agents && bash scripts/install-templates.sh ~/nanoclaw
cd ~/nanoclaw && bash ./nanoclaw.sh --template-path opensource/community-manager
```

The installer asks for the Discord bot token and writes `~/nanoclaw/.env`. Model and GitHub credentials go into the OneCLI vault when it asks. If it says to log out so the `docker` group applies, open a new SSH session and run the same `nanoclaw.sh` command again.

## 4. Discord gateway

The installer registers a user unit named `nanoclaw-v2-<install-slug>`. On the VM:

```bash
systemctl --user list-units 'nanoclaw-v2-*'
journalctl --user -u 'nanoclaw-v2-*' -n 100 --no-pager
ls ~/nanoclaw/logs
ss -tpn | grep -E 'discord|:443' || true
```

A live gateway shows a ready or identified line in `~/nanoclaw/logs` and established outbound TCP to Discord on 443. No inbound port besides SSH is required. In the developer portal, Bot → Privileged Gateway Intents → Message Content Intent must be enabled.

Send a message in a channel the bot was invited to. The log should show the inbound message. Session files appear only after an agent group exists:

```bash
find ~/nanoclaw/data/v2-sessions -name 'inbound.db' -o -name 'outbound.db'
sqlite3 ~/nanoclaw/data/v2.db 'PRAGMA integrity_check;'
```

## Tear down

```bash
cd terraform
terraform destroy
```

Destroy removes the instance, boot volume, subnet, and VCN together. An ephemeral IP is released with the VNIC. Confirm the compartment is empty afterward so a failed partial apply cannot leave a second boot volume.
