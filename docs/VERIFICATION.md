# OutStakeV2 Verification

- Verification entrypoint: `script/harness/gate.sh`
- Classification-only entrypoint: `bash script/harness/gate.sh --classify-only --changed-files <path>`
- Default local profile: `npm run gate` (`fast`)
- Fast local profile: `npm run gate:fast`
- Full local profile: `npm run gate:full`
- CI profile: `npm run gate:ci`

`fast` is the default local verdict for current work. Use `full`, `ci`, release, or merge-equivalent verification only when explicitly requested or running in that context.

Local current-work gate invocations must use exact changed-file input. Solidity changed-files mode requires diff evidence via `CHANGE_CLASSIFIER_DIFF_FILE` or `GATE_DIFF_BASE`; without it, semantic classification is blocked.

Diff evidence must not be created as persistent repository files. Prefer `GATE_DIFF_BASE=<git-ref>`; when `CHANGE_CLASSIFIER_DIFF_FILE` is needed, point it at a `mktemp` file outside the repository and remove it after `gate.sh` exits.

`full` and `ci` command gates:

| Command | Condition |
|---|---|
| `forge coverage` | `change_class=prod-semantic` and `surface_sensitivity=sensitive` |
| `slither` | same as coverage, only when changed production Solidity includes `src/**/*.sol` |

`full-subagent` is an orchestration profile, not a gate profile. It means an independent verifier is required; the verifier runs the selected `fast`, `full`, or `ci` profile.

Completion or pass claims require fresh output from the exact gate profile used for the verdict. Harness-only and docs-only changes still require a fresh gate verdict before claiming completion.

## Test Layers

- `npm run test:fast`: harness fast gate, preserving the default current-work verdict path.
- `npm run test:unit:forge`: deterministic Forge unit layer using an explicit contract include list.
- `npm run test:unit`: smoke-profile wrapper around `test:unit:forge`.
- `npm run test:position`: position unit, position fuzz, adversarial, and router proxy integration coverage.
- `npm run test:router`: router unit, router fuzz, router proxy integration, and router-position scenario coverage.
- `npm run test:yield`: SY unit, SY adapter, and oracle setter coverage.
- `npm run test:assets`: universal assets and OFT coverage.
- `npm run test:fork`: fork-only SY adapter coverage.
- `npm run test:invariant`: position invariant coverage.
- `npm run test:release`: unit layer plus invariant and fork layers under the release Foundry profile.
