# OutStakeV2

This repository is maintained as a Foundry-only workspace.

Use `forge build` to compile and `forge test -vvv` to run the Solidity suite.

Repository layout follows the domain-oriented tree below:

- `src/assets/{base,interfaces,omnichain}`
- `src/position/{interfaces}` plus root-level `OutrunStakingPosition.sol`
- `src/yield/{interfaces,adapters/*}` plus root-level `SYBase.sol`
- `src/router/{interfaces}` plus root-level `OutrunRouter.sol`
- `src/integrations/{aave,etherfi,lido,lista,sky,oracles,deployment}`
- `src/libraries` including shared helpers and `IWETH.sol`
- `test/{assets,position,router,yield,support}`
- `script/{deploy,lib,ops,process}`

The legacy `src/common/` directory has been removed.

The process layer is also wired locally:

- `npm run docs:check` validates the documented control-plane and execution-plane surfaces
- `npm run process:selftest` runs process-layer selftests for policy, review-note, and gate wiring
- `npm run quality:quick` runs scoped local checks for the changed surfaces
- `npm run quality:gate` remains the finish gate, but in-progress unrelated product changes must still be reported separately rather than masked as success
- `npm run codex:review` runs the manual / high-risk Codex review step; automatic flows only require it before the final verifier verdict for `prod-semantic` / `high-risk` production Solidity changes

Run `npm install && npm run hooks:install` once to configure the local `.githooks/pre-commit` and `.githooks/pre-push` entrypoints.
