# OpenClaw Go

OpenClaw Go deploys [OpenClaw](https://github.com/open-claw/open-claw) and
[LiteLLM](https://github.com/BerriAI/litellm) on a Google Cloud VM, with
HTTPS and Google OAuth protecting both dashboards. The entire deploy is a
single command — this guide walks you through everything you need to do first.

## Prerequisites

- **A Mac** — these instructions assume macOS
- **A Google Cloud account** with billing enabled
- **A domain name you control** — you'll add DNS records during setup
- **API keys** from the model providers you want to use:
  - [Synthetic](https://app.synthetic.computer/) (sign up and generate an API key)
  - [OpenRouter](https://openrouter.ai/) (sign up and generate an API key)
  - [Google Gemini](https://aistudio.google.com/apikey) (create an API key)

## Setup

### Step 1: Install Homebrew

If you don't already have Homebrew, install it by pasting this command in
Terminal:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

See [https://brew.sh](https://brew.sh) for details.

### Step 2: Install git and the gcloud CLI

```
brew install git
brew install --cask gcloud-cli
```

### Step 3: Clone this repo

```
git clone https://github.com/tjcrone/openclaw-go.git
cd openclaw-go
```

### Step 4: Log in to Google Cloud

```
gcloud auth login
gcloud config set project <PROJECT_ID>
```

Replace `<PROJECT_ID>` with your GCP project ID. If you don't have a project
yet, create one in the [Google Cloud Console](https://console.cloud.google.com/)
and enable billing before continuing.

### Step 5: Set up Google OAuth credentials

OpenClaw uses Google OAuth to control who can access the dashboards. You need
to create OAuth credentials in the Google Cloud Console:

1. Go to **APIs & Services > OAuth consent screen**
2. Click **Get started** and create an **External** consent screen
   - Set the app name to anything (e.g. "OpenClaw")
   - Add your email as the support email
   - Add the scopes: `openid`, `email`, `profile`
   - Add your email as a test user
3. Go to **APIs & Services > Credentials**
4. Click **Create Credentials > OAuth 2.0 Client ID**
   - Application type: **Web application**
   - Name: anything (e.g. "OpenClaw")
   - Under **Authorized redirect URIs**, add both:
     - `https://openclaw.<YOUR-DOMAIN>/oauth2/callback`
     - `https://litellm.<YOUR-DOMAIN>/oauth2/callback`
5. Copy the **Client ID** and **Client Secret** — you'll need them in the next
   step

### Step 6: Configure settings

Copy the example configuration files:

```
cp settings.conf.example settings.conf
cp litellm.env.example litellm.env
cp oauth2-proxy.env.example oauth2-proxy.env
```

Edit each file and fill in your values:

**`settings.conf`** — General deployment settings:
- `USERNAME` — the username for SSH access to the VM
- `DOMAIN` — your domain name (e.g. `example.com`)
- `ADMIN_EMAIL` — your Google account email (used for OAuth access)
- The remaining defaults (region, machine type, etc.) are fine for most users

**`litellm.env`** — API keys for model providers:
- `OPENROUTER_API_KEY` — your OpenRouter API key
- `GEMINI_API_KEY` — your Google Gemini API key
- `SYNTHETIC_API_KEY` — your Synthetic API key

**`oauth2-proxy.env`** — Google OAuth credentials from Step 5:
- `OAUTH2_PROXY_CLIENT_ID` — the Client ID you copied
- `OAUTH2_PROXY_CLIENT_SECRET` — the Client Secret you copied

### Step 7: Deploy

```
./openclawgo.sh
```

The script will:
1. Confirm your GCP project
2. Handle SSH key setup (generating a key if you don't have one)
3. Create GCP resources (network, firewall rules, static IP, storage bucket)
4. **Pause and ask you to add DNS records** — it will display the static IP
   address and the two A records you need to add at your domain registrar
5. Create the VM and wait for it to come online
6. Install and configure everything on the VM

The whole process takes roughly 10-15 minutes.

## After Deployment

Once the script finishes, your dashboards are live:

- **OpenClaw:** `https://openclaw.<YOUR-DOMAIN>`
- **LiteLLM:** `https://litellm.<YOUR-DOMAIN>`

Both dashboards are protected by Google OAuth — only the email address in
`ADMIN_EMAIL` can log in. The LiteLLM admin dashboard uses the credentials
`openclaw` / `openclaw2026`.

## Teardown

To remove all GCP resources:

```
./teardown_project.sh
```

This deletes the VM, firewall rules, service account, network, and
(optionally) the static IP. The storage bucket is preserved so that cached
TLS certificates are available for redeployment.

## Redeployment

You can run `./openclawgo.sh` again at any time to redeploy. TLS certificates
are cached in the storage bucket, so redeployments won't hit Let's Encrypt
rate limits.
