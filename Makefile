# pau-deployment-scripts Makefile
#
# Prerequisites:
#   - ETH_FROM: deployer address
#   - MAINNET_RPC_URL: chain RPC URL
#   - foundry keystore account named "deployer" (cast wallet import deployer --interactive)
#
# Note: no --verify — every contract is created by the canonical on-chain factories, whose
# implementation source lives in the component repos, not here. There are no locally-compiled
# contracts deployed by this script for Etherscan verification to act on.
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
# Post-deploy verification                                                                         #
# --------------------------------------------------------------------------------------------------
# Two modes of the same test suite (details in test/post-deploy/PostDeployTests.t.sol):
#
#   simulate — run BEFORE deploying. Runs DeployPAU.s.sol on a mainnet fork and checks its
#              result. Proves the script works against the live factories, no gas spent.
#   verify   — run AFTER deploying, BEFORE writing the activation spell. Checks the exported
#              deploy-pau-latest.json against on-chain logs: every address was created by the
#              canonical factory, `owner` is its only admin, and nothing is activated yet.
#              Catches a front-run or nonce-desynced deployment before governance onboards it.
#
# Env (optional, see .env.example for more details):
#   POSTDEPLOY_OUTPUT      verify only: export to check (default: see below)
#   POSTDEPLOY_BLOCK       fork block (default latest; pin it for a reproducible run)
#   POSTDEPLOY_FROM_BLOCK  verify only: first block scanned for logs (default: the export's
#                          `deployBlock`, so the scan window is only a few blocks wide)

POSTDEPLOY_OUTPUT ?= script/output/1/deploy-pau-latest.json

test-postdeploy-mainnet-simulate:
	POSTDEPLOY_SIMULATE=true forge test --match-path "test/post-deploy/*" -vvv

test-postdeploy-mainnet:
	POSTDEPLOY_OUTPUT=$(POSTDEPLOY_OUTPUT) forge test --match-path "test/post-deploy/*" -vvv

# --------------------------------------------------------------------------------------------------
# Deploy: PAU system                                                                               #
# --------------------------------------------------------------------------------------------------
# Input:  script/input/{chainId}/deploy-pau.json (owner, pauFactory, agentFactory, beacon, stackCount, agentCount)
# Output: script/output/{chainId}/deploy-pau-latest.json (addresses + deployBlock)

deploy-pau-mainnet:
	forge script script/DeployPAU.s.sol:DeployPAUScript \
		--sender $(ETH_FROM) --account deployer --broadcast \
		--rpc-url $(MAINNET_RPC_URL)

deploy-pau-mainnet-dryrun:
	forge script script/DeployPAU.s.sol:DeployPAUScript \
		--sender $(ETH_FROM) --account deployer --rpc-url $(MAINNET_RPC_URL)
