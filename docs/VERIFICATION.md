# OutStakeV2 Verification

- Verification entrypoint: script/harness/gate.sh
- Default local profile: npm run gate (fast)
- Fast local profile: npm run gate:fast
- Full local profile: npm run gate:full
- CI profile: npm run gate:ci
- gate (fast) is the default local verdict for current work — targeted tests on the change set.
- gate:full is the local release gate and runs the repository-wide verification profile.
- gate:ci is the CI-facing path and requires changed-files input from CI.
- For current local task completion/readiness, default to `fast` regardless of risk tier.
- Do not infer `full` from high-risk or prod-semantic risk tier alone.
- Use `full` only for explicit human requests for full/release/merge verification or CI/release-equivalent contexts.
- Local current-work gate invocations must use the exact changed-file input for tracked or intended-to-commit repository changes.
- changed-files mode for Solidity paths requires diff evidence via `CHANGE_CLASSIFIER_DIFF_FILE` or `GATE_DIFF_BASE`; without it, semantic classification is blocked.
- Mixed `harness_control` + Solidity changed-file sets are valid. Classification uses the highest risk tier in the set, review roles are the union of matched policy roles, and `gate.sh` may report `writer=mixed` for compatibility instead of blocking on multiple writer roles.
- For mixed sets whose highest risk tier is `prod-semantic` or `high-risk`, spec readiness remains a pre-implementation gate. Any spec document change still requires explicit human confirmation before implementation proceeds.
- Diff evidence must not be created as persistent repository files. Prefer `GATE_DIFF_BASE=<git-ref>`; when `CHANGE_CLASSIFIER_DIFF_FILE` is needed, point it at a `mktemp` file outside the repository and remove that file after `gate.sh` exits.
- Do not create, commit, or leave behind repository files named after `CHANGE_CLASSIFIER_DIFF_FILE`, `GATE_DIFF_BASE`, or related diff-evidence artifacts.
- `fast` is the default local verdict for current tracked or intended-to-commit repository work and should be run against the exact changed file set.
- `full` is the merge or release gate and runs the repository-wide verification profile.
- harness-only and docs-only changes still require a fresh gate verdict from the matching profile before claiming completion.
- Ignored/local scratch artifacts are not repository deliverables and do not receive a repository PASS/BLOCKED verdict from `gate.sh`. Verify them with artifact-specific checks, report that result separately, and state that repository gate is not applicable.
- If an ignored/local artifact is intended to become a formal deliverable, move it into a policy-classified tracked path or update policy so the path is classified, then run the matching gate before claiming repository readiness.
- mock-heavy unit tests do not replace semantic or integration coverage when the claim depends on upstream protocol behavior.
- Completion or pass claims for tracked or intended-to-commit repository changes require fresh output from the exact gate profile used for the verdict.

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

Foundry profile intent:

- `smoke`: lower local fuzz and invariant intensity.
- `ci`: current/default-strength fuzz and invariant intensity.
- `release`: stronger fuzz and invariant intensity for explicit release checks.
