# pau-deployment-scripts

Deployment orchestration for the PAU system: a one-shot deploy
script + Makefile that stand up a shared ALMProxy, one or more PAU stacks
(AccessControls / RateLimits / Controller), and AdministeredAgents via the canonical on-chain
factories — handing sole admin to governance (PauseProxy / SubProxy). The deployer holds no role
on anything, so there is nothing to revoke.

All mutable configuration (roles, integrations, allocator grants) is left to the activation
spell, which calls the component repos' internal init libraries — `PAUInit`
(`sky-ecosystem/diamond-pau`) and `AdministeredAgentInit`
(`sky-ecosystem/pau-administered-agent`) — with the addresses this deployment exports.

## Layout

```text
.
├── script/
│   ├── DeployPAU.s.sol                  # one-shot PAU system deploy (JSON in/out)
│   ├── dependencies/
│   │   ├── PAUDeploy.sol                # deploy one PAU stack via the canonical PAUFactory
│   │   └── AdministeredAgentDeploy.sol  # deploy one AdministeredAgent via its factory
│   ├── input/
│   │   └── {chainId}/
│   │       └── deploy-pau.json          # owner, pauFactory, agentFactory, stackCount, agentCount
│   └── output/
│       └── {chainId}/
│           └── deploy-pau-latest.json   # exported addresses (generated)
├── test/
│   ├── mainnet-fork/                    # deploy + init fork tests against the canonical factories
│   └── utils/
│       └── SpellHarness.sol             # governance-proxy stand-in that runs the init libraries
└── migrate/                             # TEMPORARY: vendored audited init libs (see migrate/README.md)
    ├── diamond-pau/
    │   └── deploy/
    │       └── PAUInit.sol              # → swaps to the lib/diamond-pau submodule once its PR lands
    └── pau-administered-agent/
        └── deploy/
            └── AdministeredAgentInit.sol
```

## Usage

```bash
cp .env.example .env    # set MAINNET_RPC_URL
forge build
forge test
```

Deploy (see the `Makefile` for the full target list):

```bash
make deploy-pau-mainnet-dryrun
make deploy-pau-mainnet
```

## Status

The two PAU init libraries are currently **vendored under `migrate/`** while their component-repo
PRs are open; see `migrate/README.md` for the submodule swap once they land.
