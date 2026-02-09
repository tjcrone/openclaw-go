#!/bin/bash
# This is to be run once on new OpenClaw instances by the
# user on first login. This installs NVM and runs the
# OpenClaw installation script.

set -e

# define color variables
GREEN='\e[92m'
NC='\e[0m' # reset color

# install miniforge
echo -e "\n\n${GREEN}Installing miniforge ...${NC}"
curl -L https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh -o install.sh && bash install.sh -b && rm install.sh
${HOME}/miniforge3/bin/conda init
source .bashrc

# install nvm (Node Version Manager)
echo -e "\n\n${GREEN}Installing nvm ...${NC}"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh" # load nvm
source "$NVM_DIR/bash_completion" # load nvm bash_completion

# install Node.js 22 (required by OpenClaw)
echo -e "\n\n${GREEN}Installing node ...${NC}"
nvm install 22
nvm use 22

# upgrade npm
npm install -g npm@11.9.0

# install pnpm (recommended by OpenClaw)
echo -e "\n\n${GREEN}Installing pnpm ...${NC}"
npm install -g pnpm

# install Docker (for LiteLLM)
echo -e "\n\n${GREEN}Installing docker ...${NC}"
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# run docker container
echo -e "\n\n${GREEN}Running LiteLLM docker container ...${NC}"
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
echo -e "\n\n${GREEN}Installing OpenClaw ...${NC}"
npm install -g openclaw@latest
source .bashrc

# run the onboarding wizard
echo -e "\n\n${GREEN}Running the onboarding wizard ...${NC}"
openclaw onboard --install-daemon

