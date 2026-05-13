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
- `src/position/{interfaces}` plus `OutrunStakingPositionUpgradeable.sol`
- `src/yield/{interfaces,adapters/{aave,aster,ethena,etherfi,lido,lista,sky}}` plus `SYBaseUpgradeable.sol` and `OutrunL2StakedTokenSYUpgradeable.sol`
- `src/router/{interfaces}` plus `OutrunRouter.sol`
- `src/integrations/{aave,aster,etherfi,lido,lista,sky}`
- `src/libraries` plus `src/libraries/oracle`
- `test/{deploy,support,upgradeable}` plus legacy-empty buckets `test/{assets,integration,position,router,security,yield}`
- `script/{deploy,deploy/deployment,harness,lib,ops}`
- `.harness/{runtime,schemas}` and `docs/`
