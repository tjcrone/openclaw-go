# OpenClaw Go

Deploy OpenClaw on GCP with LiteLLM, Ollama, and secure web access via Google OAuth.

## Prerequisites

- A GCP account with billing enabled
- The `gcloud` CLI installed and authenticated
- A domain name with DNS you can manage (e.g. Squarespace)
- API keys for your model providers (Synthetic, OpenRouter, Gemini)

## Setup

### 1. Configure settings

Copy the example files and fill in your values:

    cp litellm.env.example litellm.env
    cp oauth2-proxy.env.example oauth2-proxy.env

Edit `settings.conf` to set your username, GCP region, domain name,
admin email, and other preferences.

Edit `litellm.env` with your API keys for Synthetic, OpenRouter, and Gemini.

### 2. Set up Google OAuth

1. Go to GCP Console → APIs & Services → OAuth consent screen
2. Create an External consent screen (app name, support email, scopes: openid, email, profile)
3. Go to Credentials → Create OAuth 2.0 Client ID (Web application)
4. Add authorized redirect URIs:
   - `https://openclaw.<DOMAIN>/oauth2/callback`
   - `https://litellm.<DOMAIN>/oauth2/callback`
5. Copy the Client ID and Client Secret into `oauth2-proxy.env`

### 3. Set up DNS

Add two A records at your domain registrar pointing at your GCP static IP:
- `openclaw` → `<STATIC_IP>`
- `litellm` → `<STATIC_IP>`

Do this early — DNS propagation can take time. The static IP is created
in the next step; you can update the records after running `setup_project.sh`.

### 4. Authenticate with GCP

    gcloud auth login
    gcloud config set project <YOUR_PROJECT_ID>

### 5. Set up the GCP project

    ./setup_project.sh

This creates the VPC network, firewall rules (SSH + HTTPS), service account,
storage bucket, and static IP.

### 6. Create the VM

    ./create_instance.sh

This uploads configuration files to GCS and creates a Debian 13 VM.
The VM runs a first-boot setup script automatically (installs packages,
Caddy, swap, etc.). Wait a few minutes before logging in.

### 7. Install OpenClaw

SSH into the VM and run the install script:

    ssh <USERNAME>@<STATIC_IP>
    ./install_openclaw.sh

This installs Node.js, Docker, Ollama, LiteLLM, oauth2-proxy, OpenClaw,
and configures Caddy with SSL certificates.

### 8. Access the dashboards

- OpenClaw: `https://openclaw.<DOMAIN>`
- LiteLLM: `https://litellm.<DOMAIN>`

Both require Google OAuth login restricted to your admin email.

## Teardown

To remove all GCP resources created by `setup_project.sh`:

    ./teardown_project.sh

Note: delete the VM first (`gcloud compute instances delete <VM_NAME>
--zone=<ZONE>`) before running teardown, as the network cannot be
deleted while instances are attached.

## File Overview

| File | Description |
|------|-------------|
| `settings.conf` | GCP and domain configuration variables |
| `litellm.env` | API keys for model providers (not committed) |
| `oauth2-proxy.env` | Google OAuth credentials (not committed) |
| `litellm_config.yaml` | LiteLLM model routing and pricing configuration |
| `setup_project.sh` | One-time GCP project setup (network, firewall, IAM, bucket, IP) |
| `teardown_project.sh` | Reverse of setup_project.sh for cleanup |
| `create_instance.sh` | Upload configs and create VM |
| `setup_instance.sh` | First-boot script (runs as root): packages, Caddy, swap |
| `install_openclaw.sh` | User-run: installs everything and configures services |
| `open_tunnel.sh` | SSH tunnel fallback (optional with web proxy) |
