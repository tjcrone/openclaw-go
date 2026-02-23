#!/bin/bash
# This is to be run once on new OpenClaw instances by the
# user on first login. This installs OpenClaw and its
# dependencies and configures the system.

set -e

# check that the setup script has finished
if [ ! -f /etc/firstboot ]; then
    echo "The instance setup script is not yet finished."
    echo "Please wait a few minutes and try again."
    exit 1
fi

# define color variables
GREEN='\e[92m'
NC='\e[0m' # reset color

# install miniforge
echo -e "\n${GREEN}Installing miniforge ...${NC}"
curl -L https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh -o install.sh && bash install.sh -b && rm install.sh
${HOME}/miniforge3/bin/conda init

# install pnpm (recommended by OpenClaw)
echo -e "\n${GREEN}Installing pnpm ...${NC}"
npm install -g pnpm

# install Docker (for LiteLLM)
echo -e "\n${GREEN}Installing docker ...${NC}"
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# source settings and env
source $HOME/settings.conf
source $HOME/.config/litellm/.env

# generate internal keys (only on first run)
echo -e "\n${GREEN}Generating internal keys ...${NC}"
source $HOME/.config/litellm/.env
if [ -z "$POSTGRES_PASSWORD" ]; then
  POSTGRES_PASSWORD=$(openssl rand -hex 32)
  echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> $HOME/.config/litellm/.env
fi
if [ -z "$LITELLM_SALT_KEY" ]; then
  LITELLM_SALT_KEY=$(openssl rand -hex 32)
  echo "LITELLM_SALT_KEY=$LITELLM_SALT_KEY" >> $HOME/.config/litellm/.env
fi
if [ -z "$LITELLM_MASTER_KEY" ]; then
  LITELLM_MASTER_KEY=$(openssl rand -hex 32)
  echo "LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY" >> $HOME/.config/litellm/.env
fi

# create docker network
echo -e "\n${GREEN}Creating docker network ...${NC}"
docker network create litellm-net 2>/dev/null || true

# run PostgreSQL container
echo -e "\n${GREEN}Running PostgreSQL docker container ...${NC}"
docker stop litellm-db 2>/dev/null && docker rm litellm-db 2>/dev/null || true
docker run -d \
  --name litellm-db \
  --restart unless-stopped \
  --network litellm-net \
  -e POSTGRES_USER=litellm \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -e POSTGRES_DB=litellm \
  -v litellm-db-data:/var/lib/postgresql/data \
  postgres:17-alpine

# wait for PostgreSQL to be ready
echo -e "\n${GREEN}Waiting for PostgreSQL ...${NC}"
until docker exec litellm-db pg_isready -U litellm > /dev/null 2>&1; do
  sleep 1
done

# construct database URL
DATABASE_URL="postgresql://litellm:${POSTGRES_PASSWORD}@litellm-db:5432/litellm"

# run LiteLLM container
echo -e "\n${GREEN}Running LiteLLM docker container ...${NC}"
docker stop litellm 2>/dev/null && docker rm litellm 2>/dev/null || true
docker run -d \
  --name litellm \
  --restart unless-stopped \
  --network litellm-net \
  --env-file ~/.config/litellm/.env \
  -e DATABASE_URL=$DATABASE_URL \
  -e UI_USERNAME=openclaw \
  -e UI_PASSWORD=openclaw2026 \
  -e PROXY_BASE_URL=https://litellm.${DOMAIN} \
  -v ~/.config/litellm/litellm_config.yaml:/app/config.yaml \
  -p 127.0.0.1:4000:4000 \
  ghcr.io/berriai/litellm:main-latest \
  --config /app/config.yaml \
  --port 4000 \
  --detailed_debug

# wait for LiteLLM to be ready
echo -e "\n${GREEN}Waiting for LiteLLM ...${NC}"
until curl -s http://localhost:4000/health > /dev/null 2>&1; do
  sleep 2
done

# start oauth2-proxy
echo -e "\n${GREEN}Starting oauth2-proxy ...${NC}"
source $HOME/.config/oauth2-proxy/.env
if [ -z "$OAUTH2_PROXY_COOKIE_SECRET" ]; then
  OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -hex 16)
  echo "OAUTH2_PROXY_COOKIE_SECRET=$OAUTH2_PROXY_COOKIE_SECRET" >> $HOME/.config/oauth2-proxy/.env
fi
echo "${ADMIN_EMAIL}" > $HOME/.config/oauth2-proxy/authenticated-emails.txt
docker stop oauth2-proxy 2>/dev/null && docker rm oauth2-proxy 2>/dev/null || true
docker run -d \
  --name oauth2-proxy \
  --restart unless-stopped \
  --network host \
  -e OAUTH2_PROXY_CLIENT_ID=$OAUTH2_PROXY_CLIENT_ID \
  -e OAUTH2_PROXY_CLIENT_SECRET=$OAUTH2_PROXY_CLIENT_SECRET \
  -e OAUTH2_PROXY_COOKIE_SECRET=$OAUTH2_PROXY_COOKIE_SECRET \
  -v $HOME/.config/oauth2-proxy/authenticated-emails.txt:/etc/oauth2-proxy/authenticated-emails.txt:ro \
  quay.io/oauth2-proxy/oauth2-proxy:latest \
  --provider=google \
  --http-address=0.0.0.0:4180 \
  --upstream=static://202 \
  --set-xauthrequest=true \
  --email-domain=* \
  --authenticated-emails-file=/etc/oauth2-proxy/authenticated-emails.txt \
  --cookie-domain=.${DOMAIN} \
  --cookie-secure=true \
  --cookie-samesite=lax \
  --reverse-proxy=true \
  --skip-provider-button=true

# wait for oauth2-proxy to be ready
echo -e "\n${GREEN}Waiting for oauth2-proxy ...${NC}"
until curl -s http://127.0.0.1:4180/ping > /dev/null 2>&1; do
  sleep 1
done

# install openclaw from latest stable tag
echo -e "\n${GREEN}Cloning OpenClaw ...${NC}"
git clone https://github.com/openclaw/openclaw.git $HOME/openclaw
cd $HOME/openclaw
LATEST_TAG=$(git describe --tags --abbrev=0)
echo -e "${GREEN}Checking out ${LATEST_TAG} ...${NC}"
git checkout "$LATEST_TAG"
echo -e "\n${GREEN}Building OpenClaw ...${NC}"
pnpm install
pnpm ui:build
pnpm build
npm link
cd $HOME


# run the onboarding wizard
echo -e "\n${GREEN}Running OpenClaw onboarding ...${NC}"
openclaw onboard --non-interactive \
  --mode local \
  --auth-choice ai-gateway-api-key \
  --ai-gateway-api-key "dummy" \
  --gateway-port 18789 \
  --gateway-bind loopback \
  --install-daemon \
  --daemon-runtime node \
  --skip-skills \
  --accept-risk || true

# allow proxied UI connections without device pairing (OAuth handles auth)
echo -e "\n${GREEN}Configuring gateway for reverse proxy ...${NC}"
openclaw config set gateway.controlUi.allowInsecureAuth true
openclaw config set gateway.trustedProxies --json '["127.0.0.1"]'

# extract gateway token for Caddyfile
GATEWAY_TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.openclaw/openclaw.json'))['gateway']['auth']['token'])")

# restore cached certs from bucket (if available)
echo -e "\n${GREEN}Restoring cached certificates ...${NC}"
if gcloud storage ls gs://$BUCKET_NAME/caddy-data/ > /dev/null 2>&1; then
  sudo mkdir -p /var/lib/caddy/.local/share
  sudo gcloud storage cp -r gs://$BUCKET_NAME/caddy-data/caddy/ /var/lib/caddy/.local/share/
  sudo chown -R caddy:caddy /var/lib/caddy/.local/share/caddy/
  echo "Certificates restored from bucket"
else
  echo "No cached certificates found, Caddy will obtain new ones"
fi

# write Caddyfile
echo -e "\n${GREEN}Writing Caddyfile ...${NC}"
sudo tee /etc/caddy/Caddyfile > /dev/null <<CADDYEOF
(security_headers) {
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "SAMEORIGIN"
		Referrer-Policy "strict-origin-when-cross-origin"
	}
}

openclaw.${DOMAIN} {
	import security_headers

	@root {
		path /
		not query token=*
		not header Connection *Upgrade*
	}
	redir @root /?token=${GATEWAY_TOKEN} permanent

	handle /oauth2/* {
		reverse_proxy 127.0.0.1:4180 {
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-Uri {uri}
		}
	}

	handle {
		forward_auth 127.0.0.1:4180 {
			uri /oauth2/auth
			header_up X-Real-IP {remote_host}

			@error status 401
			handle_response @error {
				redir * /oauth2/sign_in?rd={scheme}://{host}{uri}
			}
		}
		reverse_proxy 127.0.0.1:18789 {
			header_up Host {host}
			header_up Origin https://{host}
		}
	}
}

litellm.${DOMAIN} {
	import security_headers

	redir / /ui/login permanent

	handle /oauth2/* {
		reverse_proxy 127.0.0.1:4180 {
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-Uri {uri}
		}
	}

	handle {
		forward_auth 127.0.0.1:4180 {
			uri /oauth2/auth
			header_up X-Real-IP {remote_host}

			@error status 401
			handle_response @error {
				redir * /oauth2/sign_in?rd={scheme}://{host}{uri}
			}
		}
		reverse_proxy 127.0.0.1:4000 {
			header_up Host {host}
			header_up X-Forwarded-Proto {scheme}
			header_down Location "http://litellm.${DOMAIN}" "https://litellm.${DOMAIN}"
		}
	}
}
CADDYEOF

sudo systemctl reload caddy

# back up certs to bucket (Caddy may have obtained new ones)
echo -e "\n${GREEN}Backing up certificates to bucket ...${NC}"
sleep 5
sudo gcloud storage cp -r /var/lib/caddy/.local/share/caddy/ gs://$BUCKET_NAME/caddy-data/

# generate virtual key with monthly budget
echo -e "\n${GREEN}Generating virtual key with \$${MONTHLY_BUDGET}/month budget ...${NC}"
VIRTUAL_KEY=$(curl -s 'http://localhost:4000/key/generate' \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"max_budget": '$MONTHLY_BUDGET', "budget_duration": "30d"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")
echo "Virtual key generated successfully"

# models/provider config
echo -e "\n${GREEN}Setting up the models ...${NC}"
openclaw config set models.mode "merge"
openclaw config set models.providers.litellm --json '{
  baseUrl: "http://127.0.0.1:4000/v1",
  apiKey: "'$VIRTUAL_KEY'",
  api: "openai-completions",
  models: [
    {id: "brain", name: "GPT-OSS 120B (via Synthetic)", reasoning: true, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 128000, maxTokens: 8192},
    {id: "brain-opus", name: "Claude Opus 4.6 (via OpenRouter)", reasoning: true, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 200000, maxTokens: 128000},
    {id: "brain-gemini", name: "Gemini 2.5 Flash (Thinking)", reasoning: true, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 1000000, maxTokens: 8192},
    {id: "brain-kimi", name: "Kimi K2.5 (via Synthetic)", reasoning: true, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 256000, maxTokens: 8192},
    {id: "brain-gpt", name: "GPT-OSS 120B (via Synthetic)", reasoning: true, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 128000, maxTokens: 8192},
    {id: "brain-minimax", name: "MiniMax M2.1 (via Synthetic)", reasoning: false, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 192000, maxTokens: 8192},
    {id: "brain-qwen", name: "Qwen3-235B Thinking (via Synthetic)", reasoning: true, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 128000, maxTokens: 8192},
    {id: "brain-deepseek", name: "DeepSeek V3.2 (via Synthetic)", reasoning: true, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 164000, maxTokens: 8192},
    {id: "coder", name: "Gemini 2.5 Flash", reasoning: false, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 1000000, maxTokens: 8192},
    {id: "heartbeat", name: "Gemini 2.5 Flash-Lite", reasoning: false, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 1000000, maxTokens: 8192},
    {id: "perplexity", name: "Perplexity Sonar", reasoning: false, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 128000, maxTokens: 8192}
  ]
}'

# agent defaults
echo -e "\n${GREEN}Setting up the agents ...${NC}"
openclaw config set agents.defaults --json '{
  model: {primary: "litellm/brain"},
  models: {
    "litellm/brain": {alias: "brain"},
    "litellm/brain-opus": {alias: "brain-opus"},
    "litellm/brain-gemini": {alias: "brain-gemini"},
    "litellm/brain-kimi": {alias: "brain-kimi"},
    "litellm/brain-gpt": {alias: "brain-gpt"},
    "litellm/brain-minimax": {alias: "brain-minimax"},
    "litellm/brain-qwen": {alias: "brain-qwen"},
    "litellm/brain-deepseek": {alias: "brain-deepseek"},
    "litellm/coder": {alias: "coder"},
    "litellm/heartbeat": {alias: "heartbeat"},
    "litellm/perplexity": {alias: "perplexity"}
  },
  heartbeat: {model: "litellm/heartbeat"},
  maxConcurrent: 4,
  subagents: {maxConcurrent: 8, model: "litellm/coder"},
  compaction: {memoryFlush: {enabled: true}},
  memorySearch: {
    provider: "openai",
    model: "hf:nomic-ai/nomic-embed-text-v1.5",
    remote: {
      baseUrl: "https://api.synthetic.new/openai/v1/",
      apiKey: "'$SYNTHETIC_API_KEY'"
    },
    experimental: {sessionMemory: true},
    sources: ["memory", "sessions"]
  }
}'


# restart gateway to pick up changes
echo -e "\n${GREEN}Restarting the OpenClaw gateway ...${NC}"
openclaw gateway restart


# instructions
openclaw dashboard --no-open

