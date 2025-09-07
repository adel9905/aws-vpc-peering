# AWS VPC Peering Lab (VPC A ↔ VPC B) with Bastion, ALB+ASG, and Private RDS

This project provisions a small but realistic multi‑tier setup on AWS using Terraform:

- **VPC A (10.0.0.0/16)** – the main application network
  - 2× **public** subnets (ALB + Bastion + NAT)
  - 3× **private** subnets (App in ASG + DB subnets)
  - **Internet Gateway**, **NAT Gateway**
  - **Application Load Balancer** (ALB)
  - **Auto Scaling Group** (ASG) using a Launch Template (installs Apache)
  - **Bastion host** (public EC2)
  - **RDS MySQL** in private subnets
- **VPC B (10.1.0.0/16)** – a second network used to demonstrate **VPC Peering**
  - 1× **public** subnet, **IGW**, **route table**
  - 1× test **EC2** instance
- **VPC Peering** between VPC A and VPC B and **routes** in both directions

> ⚠️ **Cost notice:** This lab creates billable resources (NAT Gateway, ALB, EC2, RDS, EIP). Tear down when finished (`terraform destroy`).


## Architecture

```mermaid
flowchart LR
  subgraph VPC_A["VPC A 10.0.0.0/16"]
    direction TB
    IGW_A[IGW]
    NAT[NAT Gateway]
    subgraph PublicA["Public subnets"]
      A1[Subnet 10.0.1.0/24]
      A2[Subnet 10.0.3.0/24]
    end
    subgraph PrivateApp["Private app subnets"]
      P1[Subnet 10.0.2.0/24]
      P2[Subnet 10.0.4.0/24]
    end
    subgraph PrivateDB["Private DB subnets"]
      D1[Subnet 10.0.5.0/24]
      D2[Subnet 10.0.6.0/24]
    end

    ALB[ALB Internet-facing]
    Bastion[Bastion EC2]
    ASG[ASG (web instances)]
    RDS[(RDS MySQL)]

    IGW_A --- A1
    IGW_A --- A2
    NAT --- A2
    ALB --- A1
    Bastion --- A1

    ASG --- P1
    ASG --- P2

    RDS --- D1
    RDS --- D2
  end

  subgraph VPC_B["VPC B 10.1.0.0/16"]
    direction TB
    IGW_B[IGW]
    B1[Subnet 10.1.1.0/24]
    VM_B[EC2 VM_B]
    IGW_B --- B1
    VM_B --- B1
  end

  Peer{{VPC Peering}}
  VPC_A <---> Peer <---> VPC_B
```


## What the Terraform code does

### Networking (VPC A)
- Creates **VPC A** `10.0.0.0/16` with:
  - Public subnets: `10.0.1.0/24` (us-east-1b) and `10.0.3.0/24` (us-east-1a) with an **IGW**.
  - Private subnets: `10.0.2.0/24`, `10.0.4.0/24` for app; `10.0.5.0/24`, `10.0.6.0/24` for DB.
  - **NAT Gateway** in a public subnet to give outbound internet to private subnets.
  - Route tables: public routes to IGW; private routes to NAT GW.

### Compute & Load Balancing (VPC A)
- **Bastion host** in the public subnet with SG allowing SSH(22), HTTP(80), Flask(5000), and ICMP (for tests).
- **ALB (HTTP:80)** across the two public subnets.
- **Launch Template** that installs Apache and writes a test `index.html`.
- **Auto Scaling Group** (min=1, desired=2, max=3) spanning the two private app subnets and registered to the ALB Target Group.

### Database (VPC A)
- **RDS MySQL 8.0** in private DB subnets via a **DB subnet group**.
- SG allowing MySQL (3306). *(See security notes below to lock this down.)*

### VPC B (Peer)
- **VPC B** `10.1.0.0/16` with one public subnet `10.1.1.0/24`, an IGW, route table, and a small EC2 instance for testing.
- SG allowing SSH(22) from anywhere and ICMP from VPC A (and 0.0.0.0/0 for simple tests).

### VPC Peering
- Creates a **peering connection** between VPC A and VPC B (same region, same account) and adds **routes** in both VPC route tables so the CIDRs can reach each other.


## Files & Variables

Key files you’ll see in this repo (single‑file setups are fine; names below are suggestions):

- `provider.tf` – AWS provider setup (region, optional default tags).
- `vpc1.tf` / app infra – VPC A networking, ALB, ASG, Bastion, RDS, NAT.
- `vpc2.tf` – VPC B networking and EC2.
- `vpc_peering.tf` – Peering and inter‑VPC routes.
- `variables.tf` – Inputs.
- `terraform.tfvars` – Your values.

### Inputs
```hcl
variable "region"     { description = "AWS region"; type = string }
variable "vpc1_cidr"  { description = "VPC A CIDR"; type = string }
variable "vpc2_cidr"  { description = "VPC B CIDR"; type = string }
variable "key_name"   { description = "EC2 key pair name"; type = string }
```

Example `terraform.tfvars`:
```hcl
region     = "us-east-1"
vpc1_cidr  = "10.0.0.0/16"
vpc2_cidr  = "10.1.0.0/16"
key_name   = "key"  # must exist in AWS EC2 -> Key Pairs
```


## How to Use

1. **Prereqs**
   - Terraform >= 1.6, AWS account, credentials configured (profile or env vars).
   - An existing **EC2 key pair** named as `var.key_name` in the target region.
   - Optional: update AMI IDs to a valid, recent Amazon Linux 2/2023 in your region.

2. **Init, validate, plan, apply**
   ```bash
   terraform init -upgrade
   terraform validate
   terraform plan -out tf.plan
   terraform apply tf.plan
   ```

3. **Outputs**
   - `bastion_public_ip` – SSH to the bastion: `ssh -i key.pem ec2-user@<ip>`
   - `bastion_private_ip` – for internal connectivity checks.
   - `rds_endpoint` – use from ASG instances or the bastion to test MySQL.


## Testing

- **Ping across peering:** from Bastion (VPC A) `ping 10.1.1.x` (VM_B in VPC B).  
- **HTTP via ALB:** the ALB DNS name should return the “Hello, World from ASG …” page.  
- **MySQL from Bastion:**  
  ```bash
  mysql -h <rds_endpoint> -u adel -p
  ```

> If ICMP isn’t working, remember AWS security groups must allow **both** directions (ingress in the target SG + egress in the source SG).


## Security Considerations (Important)

- Several SG rules are intentionally **open (0.0.0.0/0)** for lab simplicity. In real environments, restrict:
  - SSH ingress to your IP or an admin SG.
  - Flask/HTTP to the ALB or your IPs only.
  - **MySQL (3306)** should **not** be open to 0.0.0.0/0. Limit it to the ASG’s SG.
- Don’t hardcode DB passwords in code. Prefer **AWS Secrets Manager** or `TF_VAR_db_password`.
- NAT Gateways and ALBs incur **continuous cost**. Destroy when done:
  ```bash
  terraform destroy
  ```


## Cross‑Region/Account Peering (Optional)

This example assumes both VPCs are in the **same region/account**. For cross‑region/account peering:

- Add an **aliased provider** for the peer side:
  ```hcl
  provider "aws" {
    region = var.region
  }

  provider "aws" {
    alias  = "peer"
    region = var.peer_region
  }
  ```

- Use `provider = aws.peer` on resources that belong to the peer side (VPC B, its routes, etc.).
- Replace `auto_accept = true` with an explicit **accepter** resource in the peer account if different.

Example vars:
```hcl
variable "peer_region" { type = string }
```


## Troubleshooting

- **AMI not found / unsupported:** use a current AMI for your region (`aws ec2 describe-images` or AWS Console).
- **NAT Gateway errors:** ensure an **Elastic IP** is allocated and the NAT is in a **public** subnet.
- **Peering works but traffic fails:** add **routes** in *both* route tables and allow SG/Network ACLs.
- **No ALB target health:** user data must install/start Apache and open port 80 on the instance SG.

---

**Cleanup:**  
```bash
terraform destroy
```
This removes all resources created by the configuration.
