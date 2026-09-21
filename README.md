# AdmissionHub Ansible Deployment

Zero-manual-SSH deployment of AdmissionHub to AWS EC2 using Ansible roles, Ansible Vault, and Jinja2 templates. One codebase, two delivery paths:

| | Public EC2 (testing) | Private EC2 x2 (production-grade) |
|---|---|---|
| **App delivery** | Cloned from GitHub | Local `tar.gz` copied to the server |
| **Connectivity** | Direct SSH | SSH tunnel (no public IP) |
| **TLS / HTTPS** | Let's Encrypt (certbot) | Route 53 → ALB → AWS ACM (no certbot) |
| **Playbook** | `deploy-admissionhub.yml` | `private_ec2_deploy.yml` |

Terraform provisions the infrastructure. Ansible configures everything inside it, so no one has to log in and set up a server by hand.

## Architecture

```
                         ┌──────────────┐
   Users ──HTTPS──▶ Route 53 ─▶ ALB (ACM cert) ─▶ Private EC2 x2
                         └──────────────┘          (Docker + Nginx + app)
                                                        ▲
   Your machine ──SSH tunnel via reachable host─────────┘
        │                                    (Ansible + tar.gz artifact)
        └──direct SSH──▶ Public EC2 (git clone + Let's Encrypt)
```

## Project structure

```
.
├── ansible.cfg
├── ansible-vault.pass              # vault password file 
├── deploy-admissionhub.yml         # public EC2: clone from GitHub + certbot
├── private_ec2_deploy.yml          # private EC2s: tar.gz artifact, ALB/ACM TLS
├── group_vars/
│   └── web/
│       ├── admissionhub.yml        # app variables
│       └── db-vault.yml            # encrypted DB credentials (Ansible Vault)
├── inventories/
│   └── production                  # public + private hosts
└── roles/
    ├── docker                      # install and configure Docker
    ├── dependencies                # system packages
    ├── clone-or-update             # clone or pull the app from GitHub
    ├── configuration               # env files + nginx.conf from templates
    ├── deployment                  # bring the application up
    ├── cleanup                     # remove temporary files and artifacts
    ├── local-zip-conf              # config templates for the artifact path
    └── local-zip-deployer          # copy and extract the local tar.gz
```

Each role does one job, which keeps debugging simple and lets both playbooks reuse the same pieces.

## Prerequisites

- Ansible installed on your control machine
- SSH key access to the public instance, and to a host that can reach the private instances
- Infrastructure already provisioned (EC2, Route 53, ALB, ACM certificate)
- For the private path: the application built locally as a `tar.gz`

## Setup

1. **Clone this repo**
   ```bash
   git clone <your-repo-url>
   cd <your-repo>
   ```

2. **Create the vault password file** and make sure it is ignored by Git
   ```bash
   openssl rand -base64 2048 > ansible-vault.pass
   echo "ansible-vault.pass" >> .gitignore
   ```

3. **Encrypt your database credentials**
   ```bash
   ansible-vault encrypt group_vars/web/db-vault.yml
   ```

4. **Edit the inventory** at `inventories/production` with your host addresses.

## Reaching private instances (SSH tunneling)

Ansible is agentless and runs over SSH, but the private instances have no public IP. Ansible reaches them by tunneling through AWS SSM ProxyCommand. The playbooks don't change; only the connection path does.

Example using SSM's `ProxyCommand` in the inventory (adjust to match your setup):

```ini
[private]

private_server1 ansible_host=i-<your-private-server-id> ansible_user=ubuntu ansible_ssh_private_key_file=<your-key-path>
private_server2 ansible_host=i-<your-private-server-id> ansible_user=ubuntu ansible_ssh_private_key_file=<your-key-path> 

[private:vars]

ansible_ssh_common_args=-o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"
```

The tunnel is only the transport. No manual login or configuration happens on the servers.

## Usage

**Public EC2 (clone from GitHub, HTTPS via Let's Encrypt):**
```bash
ansible-playbook deploy-admissionhub.yml
```

**Private EC2s (local tar.gz, TLS handled by ALB + ACM):**
```bash
ansible-playbook private_ec2_deploy.yml
```

Useful flags:
```bash
--check          # dry run
--limit private-server1    # target a single host
-vvv             # verbose output for debugging connections
```

## Configuration

Jinja2 templates render per-environment config:

| Template | Output |
|---|---|
| `admissionhub.env.j2` | Backend environment file |
| `frontend.env.j2` | Frontend environment file |
| `nginx.conf.j2` | Nginx configuration |

Variables live in `group_vars/web/admissionhub.yml`. Secrets live only in `group_vars/web/db-vault.yml`, encrypted with Ansible Vault.

## Security notes

- Private instances are not exposed to the internet; TLS terminates at the ALB
- Use least-privilege SSH keys and restrict the jump host's security group to your IP

## Design decisions

- **Two delivery models on purpose.** Git clone on the public box for quick testing; a pre-built artifact on private boxes that can't reach GitHub.
- **TLS at the edge.** Comparing certbot on the instance with ACM at the load balancer shows why production setups terminate TLS at the ALB.
- **Roles over a monolithic playbook.** Small, single-purpose roles that can be reused across both paths.

## Roadmap

- [ ] Feed Terraform outputs directly into the Ansible inventory
- [ ] Add idempotency and lint checks in CI (`ansible-lint`)
- [ ] Add rollback of the previous artifact

