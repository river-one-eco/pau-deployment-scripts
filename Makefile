# pau-deployment-scripts Makefile
#
# Prerequisites:
#   - ETH_FROM: deployer address
#   - MAINNET_RPC_URL: chain RPC URL
#   - MAINNET_API_KEY: Etherscan key (for --verify)
#   - foundry keystore account named "deployer" (cast wallet import deployer --interactive)
#
# Deploys the PAU system: one shared ALMProxy + `stackCount` PAU stacks wired to it +
# `agentCount` AdministeredAgents, all via the canonical on-chain factories, with the owner
# (PauseProxy / SubProxy) as sole admin (one shot, JSON in/out). Everything else — roles,
# integrations, allocator grants — happens in the activation spell via the component repos'
# init libraries (PAUInit, AdministeredAgentInit).

# --------------------------------------------------------------------------------------------------
# Build & Test                                                                                     #
# --------------------------------------------------------------------------------------------------

build:
	forge build

test:
	forge test

clean:
	forge clean

test-fork-mainnet:
	forge test --match-path "test/mainnet-fork/*" -vvv

# --------------------------------------------------------------------------------------------------
# Deploy: PAU system                                                                               #
# --------------------------------------------------------------------------------------------------
# Input:  script/input/{chainId}/deploy-pau.json (owner, pauFactory, agentFactory, stackCount, agentCount)
# Output: script/output/{chainId}/deploy-pau-latest.json

deploy-pau-mainnet:
	forge script script/DeployPAU.s.sol:DeployPAUScript \
		--sender $(ETH_FROM) --account deployer --broadcast \
		--verify --retries 10 --delay 10 --rpc-url $(MAINNET_RPC_URL)

deploy-pau-mainnet-dryrun:
	forge script script/DeployPAU.s.sol:DeployPAUScript \
		--sender $(ETH_FROM) --account deployer --rpc-url $(MAINNET_RPC_URL)
