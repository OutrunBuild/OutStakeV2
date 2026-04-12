# OutStakeV2

Foundry-only workspace.

Project commands:

- `npm run lint`
- `npm run build`
- `npm run test`
- `npm run gas:report`

Harness commands:

- `npm run gate:fast`
- `npm run gate`
- `npm run gate:ci`

Harness machine truth is `.harness/policy.json`. Enforcement runs through `script/harness/gate.sh`. Local hooks in `.githooks/` call the same gate entrypoints when enabled.

Repository layout:

- `src/assets/{base,interfaces,omnichain}`
- `src/position/{interfaces}` plus root-level `OutrunStakingPosition.sol`
- `src/yield/{interfaces,adapters/*}` plus root-level `SYBase.sol`
- `src/router/{interfaces}` plus root-level `OutrunRouter.sol`
- `src/integrations/{aave,etherfi,lido,lista,sky,oracles,deployment}`
- `src/libraries`
- `test/{assets,position,router,yield,support}`
- `script/{deploy,lib,ops}`
