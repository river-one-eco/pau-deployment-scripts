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
│   │       └── deploy-pau.json          # owner, pauFactory, agentFactory, beacon, stackCount, agentCount
│   └── output/
│       └── {chainId}/
│           └── deploy-pau-latest.json   # exported addresses (generated)
├── test/
│   ├── mainnet-fork/                    # deploy + init fork tests against the canonical factories
│   ├── post-deploy/                     # verifies a real deployment's output JSON against mined logs
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
make test-postdeploy-mainnet-simulate   # runs the script on a fork and verifies the result
make deploy-pau-mainnet-dryrun
make deploy-pau-mainnet
make test-postdeploy-mainnet            # required before the spell is written from the output JSON
```

### Post-deploy verification

`forge script` exports the addresses it *simulated*, predicted from the factories' nonces. The
factories are permissionless, so any factory call mined between simulation and broadcast shifts
the real addresses: the exported ones may then belong to contracts created by someone else, for
someone else. `test/post-deploy/` asserts, for every exported contract, that:

- the canonical factory emitted its `<Component>Deployed` event for that exact address (and, for
  Controllers, with this stack's AccessControls / ALMProxy / RateLimits as constructor arguments);
- its complete log history is the single constructor admin grant to `owner` (sender = factory)
  and nothing else — the only way to prove sole admin on the non-enumerable ALMProxy / RateLimits;
- `owner` is admin, no `CONTROLLER` / `ALLOCATOR` role is granted yet, Controller wiring and
  beacon match, and the output agrees with `script/input/{chainId}/deploy-pau.json`.

The same assertions run in two modes:

- `make test-postdeploy-mainnet-simulate` (`POSTDEPLOY_SIMULATE=true`): runs `DeployPAU.s.sol` on
  a mainnet fork inside the test and checks what it produced from the logs recorded while it ran.
  Use it before deploying to prove the script and input file work against the live factories.
  The script's output file is restored afterwards.
- `make test-postdeploy-mainnet` (`POSTDEPLOY_OUTPUT=<path>`): reconciles the exported
  `script/output/{chainId}/deploy-pau-latest.json` against the chain from mined logs
  (`eth_getLogs` on `MAINNET_RPC_URL`). Run it after the real deployment and
  before the activation spell, which legitimately adds events. Pin `POSTDEPLOY_BLOCK` to a block
  right after the deployment for a reproducible run.

The suite is skipped when neither variable is set.

## Status

The two PAU init libraries are currently **vendored under `migrate/`** while their component-repo
PRs are open; see `migrate/README.md` for the submodule swap once they land.
