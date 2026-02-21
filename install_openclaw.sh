#!/bin/bash
# This is to be run once on new OpenClaw instances by the
# user on first login. This installs NVM and runs the
# OpenClaw installation script.

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

# install nvm (Node Version Manager)
echo -e "\n${GREEN}Installing nvm ...${NC}"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh" # load nvm
source "$NVM_DIR/bash_completion" # load nvm bash_completion

# install Node.js 22 (required by OpenClaw)
echo -e "\n${GREEN}Installing node ...${NC}"
nvm install 22
nvm use 22

# upgrade npm
npm install -g npm@11.9.0

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

# generate internal keys
echo -e "\n${GREEN}Generating internal keys ...${NC}"
POSTGRES_PASSWORD=$(openssl rand -hex 32)
LITELLM_SALT_KEY=$(openssl rand -hex 32)
LITELLM_MASTER_KEY=$(openssl rand -hex 32)
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> $HOME/.config/litellm/.env
echo "LITELLM_SALT_KEY=$LITELLM_SALT_KEY" >> $HOME/.config/litellm/.env
echo "LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY" >> $HOME/.config/litellm/.env

# create docker network
echo -e "\n${GREEN}Creating docker network ...${NC}"
docker network create litellm-net

# run PostgreSQL container
echo -e "\n${GREEN}Running PostgreSQL docker container ...${NC}"
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
docker run -d \
  --name litellm \
  --restart unless-stopped \
  --network litellm-net \
  --env-file ~/.config/litellm/.env \
  -e DATABASE_URL=$DATABASE_URL \
  -v ~/.config/litellm/litellm_config.yaml:/app/config.yaml \
  -p 4000:4000 \
  ghcr.io/berriai/litellm:main-latest \
  --config /app/config.yaml \
  --port 4000 \
  --detailed_debug

# wait for LiteLLM to be ready
echo -e "\n${GREEN}Waiting for LiteLLM ...${NC}"
until curl -s http://localhost:4000/health > /dev/null 2>&1; do
  sleep 2
done

# install openclaw
echo -e "\n${GREEN}Installing OpenClaw ...${NC}"
npm install -g openclaw@2026.2.15
export PATH="$(dirname $(which node)):$PATH"


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
  --accept-risk

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
    {id: "brain-opus", name: "Claude Opus 4.6 (via OpenRouter)", reasoning: true, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 200000, maxTokens: 8192},
    {id: "brain-gemini", name: "Gemini 2.5 Flash (Thinking)", reasoning: true, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 1000000, maxTokens: 8192},
    {id: "brain-kimi", name: "Kimi K2.5 (via Synthetic)", reasoning: true, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 262000, maxTokens: 8192},
    {id: "brain-gpt", name: "GPT-OSS 120B (via Synthetic)", reasoning: true, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 128000, maxTokens: 8192},
    {id: "brain-minimax", name: "MiniMax M2.1 (via Synthetic)", reasoning: false, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 1000000, maxTokens: 8192},
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
  subagents: {maxConcurrent: 8, model: "litellm/coder"}
}'


# restart gateway to pick up changes
echo -e "\n${GREEN}Restarting the OpenClaw gateway ...${NC}"
openclaw gateway restart


# instructions
openclaw dashboard --no-open

