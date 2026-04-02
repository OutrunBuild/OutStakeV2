# Process

本目录承载 `OutStakeV2` 当前已落盘的 Harness process 真源。

当前仓库的业务域目录模型为：

- `src/assets/{base,interfaces,omnichain}`
- `src/position/{interfaces}` plus root-level `OutrunStakingPosition.sol`
- `src/yield/{interfaces,adapters/*}` plus root-level `SYBase.sol`
- `src/router/{interfaces}` plus root-level `OutrunRouter.sol`
- `src/integrations/{aave,etherfi,lido,lista,sky,oracles,deployment}`
- `src/libraries` including shared helpers and `IWETH.sol`
- `test/{assets,position,router,yield,support}`
- `script/{deploy,lib,ops,process}`

历史遗留的 `src/common/` 目录已移除。

- `change-matrix.md`：路径到角色、证据和命令的触发矩阵
- `policy.json`：machine-readable gate / review-note / ownership 策略
- `review-notes.md`：review note 字段、证据链和自动发现约束
- `subagent-workflow.md`：control-plane、agent-plane 与 execution-plane 的阶段流

对应的 execution-plane 脚本位于 `script/process/`，并由 `npm run docs:check`、`npm run process:selftest`、`npm run quality:quick`、`npm run quality:gate` 消费。

当前工作树如果存在与本流程任务无关的产品在制改动，`verifier` 可以把局部流程验证与 repo-wide compile / finish gate 结果分开归因；不得把未验证的全仓状态表述为通过。
