#!/bin/bash
# This is to be run once on new OpenClaw instances by the
# user on first login. This installs NVM and runs the
# OpenClaw installation script.

set -e

# define color variables
GREEN='\e[92m'
NC='\e[0m' # reset color

# install miniforge
echo -e "\n${GREEN}Installing miniforge ...${NC}"
curl -L https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh -o install.sh && bash install.sh -b && rm install.sh
${HOME}/miniforge3/bin/conda init
source .bashrc

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

# run docker container
echo -e "\n${GREEN}Running LiteLLM docker container ...${NC}"
docker run -d \
  --name litellm \
  --restart unless-stopped \
  --env-file ~/.config/litellm/.env \
  -v ~/.config/litellm/litellm_config.yaml:/app/config.yaml \
  -p 4000:4000 \
  ghcr.io/berriai/litellm:main-latest \
  --config /app/config.yaml \
  --port 4000 \
  --detailed_debug

# install openclaw
echo -e "\n${GREEN}Installing OpenClaw ...${NC}"
npm install -g openclaw@latest
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

# models/provider config
echo -e "\n${GREEN}Setting up the models ...${NC}"
source $HOME/.config/litellm/.env
openclaw config set models.mode "merge"
openclaw config set models.providers.litellm --json '{
  baseUrl: "http://127.0.0.1:4000/v1",
  apiKey: "'$LITELLM_MASTER_KEY'",
  api: "openai-completions",
  models: [
    {id: "brain", name: "DeepSeek R1 (via OpenRouter)", reasoning: true, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 128000, maxTokens: 8192},
    {id: "coder", name: "Gemini 2.5 Flash", reasoning: false, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 1000000, maxTokens: 8192},
    {id: "cheap", name: "Gemini 2.5 Flash-Lite", reasoning: false, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 1000000, maxTokens: 8192},
    {id: "brain-lite", name: "Gemini 2.5 Flash (Thinking)", reasoning: true, input: ["text", "image"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 1000000, maxTokens: 8192},
    {id: "researcher", name: "Perplexity Sonar", reasoning: false, input: ["text"], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 128000, maxTokens: 8192}
  ]
}'

# agent defaults
echo -e "\n${GREEN}Setting up the agents ...${NC}"
openclaw config set agents.defaults --json '{
  model: {primary: "litellm/brain"},
  models: {
    "litellm/brain": {alias: "brain"},
    "litellm/brain-lite": {alias: "brain-lite"},
    "litellm/coder": {alias: "coder"},
    "litellm/cheap": {alias: "cheap"},
    "litellm/researcher": {alias: "researcher"}
  },
  heartbeat: {model: "litellm/cheap"},
  maxConcurrent: 4,
  subagents: {maxConcurrent: 8, model: "litellm/coder"}
}'

# restart gateway to pick up changes
echo -e "\n${GREEN}Restarting the OpenClaw gateway ...${NC}"
openclaw gateway restart


# instructions
openclaw dashboard --no-open

