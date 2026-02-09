#!/bin/bash

set -e

# define color variables
GREEN='\e[92m'
NC='\e[0m' # reset color

# models/provider config
source .bashrc
echo -e "\n\n${GREEN}Setting up the models ...${NC}"
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
echo -e "\n\n${GREEN}Setting up the agents ...${NC}"
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
echo -e "\n\n${GREEN}Restarting the OpenClaw gateway ...${NC}"
openclaw gateway restart

