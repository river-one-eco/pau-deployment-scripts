# Temporary vendored init libraries

The fork tests here run the PAU init libraries exactly as a governance spell would. Those
libraries are canonically owned by their component repos:

| File | Canonical home |
| ---- | -------------- |
| `diamond-pau/deploy/PAUInit.sol` | `sky-ecosystem/diamond-pau` → `deploy/PAUInit.sol` |
| `pau-administered-agent/deploy/AdministeredAgentInit.sol` | `sky-ecosystem/pau-administered-agent` → `deploy/AdministeredAgentInit.sol` |

They are **vendored here temporarily** while their PRs are open. Once those land, this folder is
deleted and the two repos are added as pinned submodules:

```bash
git submodule add https://github.com/sky-ecosystem/diamond-pau            lib/diamond-pau
git submodule add https://github.com/sky-ecosystem/pau-administered-agent lib/pau-administered-agent
```

Then flip the imports in `test/utils/SpellHarness.sol` (and any test importing `PAUInstance`):

- `../../migrate/diamond-pau/deploy/PAUInit.sol` → `../../lib/diamond-pau/deploy/PAUInit.sol`
- `../../migrate/pau-administered-agent/deploy/AdministeredAgentInit.sol` → `../../lib/pau-administered-agent/deploy/AdministeredAgentInit.sol`

The vendored file contents are byte-identical to the component-repo versions, so the swap is an
imports-only diff.
