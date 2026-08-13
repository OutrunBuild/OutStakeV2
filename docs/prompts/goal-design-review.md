对设计稿或实现计划做闭环审查。审查必须先正面证明方案在所有路径下成立，再裁决 finding；不得把「未提出问题」当作方案正确的证据。优先证明问题真实、分层正确且修复可执行；不要用风格偏好制造 finding。

设计稿：docs/superpowers/specs/2026-08-13-f44-keepwrapredeem-design.md
实现计划：docs/superpowers/plans/2026-08-13-f44-keepwrapredeem.md

## Input Contract

输入使用以下最小结构：

artifacts:
  - path: path/to/artifact.md
    type: design | plan | auto
  - path: path/to/another-artifact.md
    type: design | plan | auto

base_design: optional/path/to/design.md
mode: review | review-and-fix   # 默认 review-and-fix

`artifacts` 的每一项独立分类。`type: auto` 时根据该文件实际内容分类。`base_design` 是实现计划所依赖的基准设计，未提供时只在确实影响判断时提出最小的 Open Question。

路径只是输入，不暗示固定业务、固定文件集合或固定 writer。具体 writer、reviewer、ownership、人工确认与 verification 必须遵循仓库的 `AGENTS.md`、policy 和 gate 输出。`mode: review` 全程只读，不修改任何文件；`mode: review-and-fix` 才可在裁决后进入修复。

## Canonical State

所有 planning-artifact 候选严格使用以下状态：

candidate → KEEP | KILL | UNPROVEN → confirmed KEEP → writer fixed → PASS | FAIL | BLOCKED

- `candidate`：reviewer 基于证据提出的待核验问题。
- `KEEP`：通过全部六道门，仍待主会话独立裁决。
- `KILL`：未通过任一道门，进入 `Filtered Out`，并记录失败的门。
- `UNPROVEN`：缺少必要事实或无法证明根因，进入 `Open Questions`；material `UNPROVEN` 需要人工决定。
- `confirmed KEEP`：主会话核对后确认的 finding，才可交给 writer。
- `writer fixed`：policy 指定的 writer 已完成修复，等待验证。
- `PASS`、`FAIL`、`BLOCKED`：修复验证的最终结果。

设计层 artifact 额外使用方案级 soundness 状态（与上述 finding 状态平行、不可混用）：

- `Sound`：Phase 0.5 的资金守恒、会计守恒、数值边界、状态机性质、结算顺序均已有正向证明，且无路径违反守恒或不变量。
- `Sound with Caveats`：证明成立，但存在被设计显式接受且范围受控的近似（如已知舍入误差上界）；每个 caveat 需标注是否已获人工确认。
- `Unproven Sound`：任一项无法证明、出现反例路径，或设计稿缺少证明所需事实；阻断该 artifact 进入 Phase 1 的 finding 裁决，缺口转为 Open Questions。

severity 与上述状态分离；`Minor` 也必须是已证明的 `KEEP`。`TRUE PROBLEM` / `FALSE POSITIVE` 只用于单独 route 到 `adjudicate-finding` 的代码或安全 finding，不作为本文档审查的主状态。

## Phase 0 — 分类与证据清单

1. 逐个读取 artifact，确定其为 `design`、`plan` 或已解析的 `auto` 类型。
2. 有设计稿和实现计划时：设计稿按设计层审查，计划按计划层审查，并额外检查两者 alignment。不要把整个文件集合粗暴标为 `mixed`。
3. 只建立 evidence manifest，不产生共享的结论性“全局认知摘要”。每条记录至少包含：

   - `artifact`：输入路径
   - `type`：实际分类
   - `location`：`file:line` 与节标题
   - `evidence`：支持后续核验的原文事实
   - `relation`：仅在需要时标明与 `base_design` 或另一 artifact 的对应段落

4. 若必需上下文缺失，记录为 `UNPROVEN` 的最小问题；不要猜测或以默认实现填补空白。

## Phase 0.5 — 方案正向证明（设计层前置，强阻断）

任何 `design` artifact 进入 Phase 1 的 finding 裁决前，必须先完成本层正向证明。这是「方案在所有合法路径下是否成立」的方案级证明，**不**复用六道门（六道门只裁决单个 finding 的真伪）。证明只能基于 artifact 明示的事实；任何步骤无法证明时，整个 artifact 标记为 `Unproven Sound`，不得以「未发现问题」默认其成立。

`plan` artifact 不在本层证明；若其 `base_design` 仍为 `Unproven Sound`，记录为阻断性 Open Question。

### 模型建构

逐项显式建立下列模型；缺失即 `Unproven Sound`：

- **资金流图**：列出所有参与方（合约/账户/协议）与所有 token，每个动作在每条边上画出「谁付出、谁收到、数量表达式」，标明 source/sink。若设计未区分 token，或出现无 source/sink 的边，立即标记。
- **数学模型**：把每个被设计依赖的关键量写成表达式（含常量、fee、rate、share 等），写明变量取值域、单位（decimals）、舍入方向（向下/向上/四舍五入）与舍入次数。设计稿只给自然语言而无数值表达式时，标记 `Unproven Sound`。
- **状态机**：列出关键状态变量、取值域，以及每个动作的状态迁移；标明初始状态、终态、不可达状态、自环与回退。
- **路径空间**：枚举合法调用顺序（含并发、重入、flash 还款、部分填充、退款/取消），并显式标注哪些组合被设计判为非法（及判据）。

### 守恒与边界证明

对模型建构的结果，逐一给出证明或反例：

- **资金守恒**：对每个动作证明「所有 token 的 ∑Δbalance == 应计增量」恒等式在每个路径下成立；任何 fee/奖励/损耗必须有明确去向（sink）且被显式记账。存在「凭空产生 / 凭空消失」的 token 即证明失败。
- **会计守恒**：若存在 share/credit/debt 这类内部账目，证明其与底层资产的一一对应在每个路径下成立，包括单独的存款、取款、部分取款、清算路径。
- **数值边界**：对表达式在 `0`、`max`（type 上限）、单 token 精度、跨精度（18 vs 6）情形下检查；明确每个除法的舍入方向是否偏向协议/用户，并说明累积误差上界。
- **状态机性质**：证明不变量在每个迁移后保持；标注任何路径后不变量可能被破坏的点。
- **结算顺序**：检查检查-生效-交互（CEI）、先扣后还、重入锁等是否在每条结算路径上被设计明确要求；顺序未由设计固定即标记。

### 证明结论

每个 `design` artifact 输出一个方案级证明结论：

- `Sound`：上述每一项均有正向证明，且无路径违反守恒/不变量。
- `Sound with Caveats`：证明成立，但存在被设计显式接受、且范围受控的近似（如已知舍入误差上界）；逐条列出 caveats 并标注是否需人工确认。
- `Unproven Sound`：任一项无法证明、出现反例路径，或设计稿缺少证明所需事实。此结论是阻断性的：该 artifact 不得进入 Phase 1 的 finding 裁决；其缺口转为 Open Questions，其中资金守恒、会计守恒、结算顺序相关的缺口为 material `UNPROVEN`，必须有人工决定。

Phase 0.5 的证明产物（模型、恒等式、路径枚举、反例或证明步骤）作为 evidence manifest 的一部分保留，供 Phase 1 及 red-team 引用。

## Phase 1 — 分层、只读审查

为每个 layer 独立生成 candidate。reviewer 只读：不得编辑 artifact、不得自行修复、不得把未核验观察写成 finding。审查角色和数量由仓库 policy 决定，不预设固定数量或通用 agent 名称。

### 设计层（`design`）

Phase 0.5 已对资金流守恒、数学模型、状态机与路径空间完成正向证明；本层在此基础上做 finding 裁决。审查目标、行为契约、边界、关键不变量、兼容性、数据或状态模型、权限与安全假设、迁移或升级边界、影响正确性的关键顺序，以及验收级验证证据。同时审查最小性与工艺：目标与约束是否恰好覆盖问题，没有引入无关 scope 或未 justify 的抽象、可配置项、可选路径；状态/数据/控制流是否直线，没有用补丁堆叠掩盖根因或留下同层耦合。不要强迫设计稿给出测试文件名、每条断言、辅助函数或其他应留给实现计划的机械细节。

设计层 candidate 必须基于 Phase 0.5 的正向证明产物生成：证明中发现的守恒违反、不变量破坏点、反例路径、数值边界问题直接成为 candidate；`Sound with Caveats` 中未被人工确认的 caveat，以及 `Unproven Sound` 中可定位到具体决策的缺口，也转为 candidate。不得绕过 Phase 0.5 的证明、仅凭直觉或偏好生成设计层 finding。

### 计划层（`plan`）

审查计划本身的可执行性：目标文件或明确 discovery 步骤、具体 edit intent、依赖与任务顺序、验收标准、验证命令或可观察结果、回滚与检查点（相关时）。同时审查最小性与工艺：每个任务是否为达成目标所需的最小改动，没有引入超出 `base_design` 或非必要的抽象、可配置项、预插桩或「为以后留的口子」；步骤是否直线可执行，没有补丁叠补丁式的修复编排或隐藏的跨任务耦合。再与 `base_design` 或已输入的设计稿逐项对齐，确认计划没有遗漏、扭曲或擅自扩大设计决策。

### 六道门

每个 candidate 必须按 `review-planning-artifacts` 的六道门逐项证明，任一门失败即 `KILL`：

1. **Grounding**：问题是否由 artifact 明示，而非偏好或臆测？
2. **Novelty**：artifact 是否已经在其他位置解决？
3. **Concrete impact**：能否指出具体的实现、审查或维护失败？
4. **Root cause**：能否命名损坏的决策、假设或顺序，而非重述症状？
5. **Layer match**：它是否属于当前 artifact 的抽象层？
6. **Devil's advocate**：主动反驳后，是否仍无法推翻？

根因无法证明时使用 `UNPROVEN`，不要给出确定性修复。低层 implementation note 进入 `Implementation Follow-ups`，不拿来阻塞设计层；计划层缺失的执行细节则是直接候选。

## Phase 2 — 主会话裁决与一次 red-team

主会话必须独立核对 evidence manifest、location、实际影响、根因与 layer match；不要直接采纳 reviewer 结论。随后：

1. 去重相同问题，分配稳定 finding ID，并保留关联 artifact 与 `file:line`。
2. 将每个 candidate 裁决为 `confirmed KEEP`、`KILL` 或 `UNPROVEN`。
3. 对每个 `confirmed KEEP`，提出至少两个不同策略类的修复方向，在相同抽象层比较：是否消除根因、增加的 scope、是否保留已声明约束、另一位工程师能否无需重新解释即可执行。选择消除根因且新增 scope 最小的方案，并说明其为何优于另一方案。
4. 出现任一 high-risk marker 时，只派一次独立 red-team：涉及安全、资金流、权限语义、迁移安全、升级行为、用户标记为 high-stakes，或存在 material `UNPROVEN`。red-team 只做两件事：尝试 `KILL` confirmed findings，或以更简单/更正确的方案 `BEAT` 已选修复。它不得新增未经主会话裁决的问题。
5. 合并 red-team 结果：被推翻的 finding 转入 `Filtered Out`；被击败的修复替换为更优方案；其余 findings 保持裁决结果。

## Phase 3 — 受控修复

仅 `confirmed KEEP` 可进入 writer。`mode: review` 在 Phase 2 后结束，不写入文件，并在 readiness 中明确未关闭的 finding 或人工决定。

`mode: review-and-fix` 时，将已裁决 finding、选定修复、受影响 artifact 和验收证据交给 policy 指定 writer。reviewer 与裁决角色不得写文件。修复只覆盖 confirmed finding 及其必要的直接依赖，不把任何固定文档目录当作默认修复目标。

具体 ownership、harness、writer 路由和 gate 操作留给目标仓库的控制文件执行；不要在本提示词中复制或展开这些仓库细节。

## Phase 4 — 修复验证与针对性复审

1. 使用 `fix-review` 只审本轮修复、原 finding 的依赖段和直接邻接风险，确认根因已消除且没有引入同层矛盾。
2. 仅当候选实际属于代码或安全问题、且需要专门真伪核验时，route 到 `fp-check`；不要因文档高风险就默认运行它。
3. 已跟踪文件使用精确 changed-file gate；本地 artifact 使用与其类型相符的验证，例如格式、链接、命令、可执行步骤或验收证据检查。不要对未跟踪本地 artifact 强行套用 changed-file gate。
4. 普通修复完成 targeted re-review。只有修复改变 scope、关键不变量、权限、资金流或公共行为时，才回到 Phase 1 做 full re-review。
5. `FAIL` 返回对应 writer；缺少外部事实、权限或人工决定时标为 `BLOCKED`。复审不因“又发现一处小细节”而无限扩大到更低实现层。

## Exit

在 `mode: review-and-fix` 中，仅同时满足以下条件时结束闭环：

- 每个 `design` artifact 的方案级证明结论为 `Sound` 或 `Sound with Caveats`（无 `Unproven Sound`）；
- `confirmed KEEP == 0`；
- 每个 material `UNPROVEN` 都已有明确人工决定；
- 本轮修复的验证已完成，且没有 `FAIL` 或 `BLOCKED`。

若同一 stable finding 连续两轮仍未关闭，停止循环并请求人工决定；不要机械地跑固定轮数。`无新增 KEEP` 不是单独的退出条件。

## Output Contract

最终输出使用中文，保留技术标识符、路径、命令与精确错误文本。按以下结构输出；没有内容的区块写“无”。

### 输入摘要

- mode、`base_design`（如有）与每个输入路径。

### Artifact Classification

- 每个 artifact 的实际类型、审查 layer 与所用基准。

### Soundness Proof（仅 `design` artifact）

- 每个 `design` artifact 的方案级证明结论（`Sound` / `Sound with Caveats` / `Unproven Sound`）。
- 资金流图：参与方、token、每条边的数量表达式、source/sink。
- 数学模型：关键量表达式、取值域、单位、舍入方向。
- 状态机：状态变量、取值域、迁移、不变量。
- 路径空间：枚举的合法顺序、被判定为非法的组合及判据。
- 守恒与边界证明结果：资金守恒、会计守恒、数值边界、状态机性质、结算顺序逐项的证明或反例。
- `Sound with Caveats` 列出每个 caveat 及是否已获人工确认；`Unproven Sound` 列出阻断性缺口。

### Findings

- `[finding ID] [Blocking|Major|Minor] [confirmed KEEP|writer fixed|PASS|FAIL|BLOCKED] [file:line]`
  - Problem：
  - Impact：
  - Root cause：
  - Fix：选定方案、至少两个策略类替代方案及选择理由。
  - Verdict：六道门结果、主会话裁决，以及 red-team 结果（如运行）。

### Filtered Out

- 被 `KILL` 的 candidate 与失败的门；不要编造该区块的内容。

### Open Questions

- 每个 `UNPROVEN` 的缺失事实、最小提问和需要的人类决定。

### Implementation Follow-ups

- 不改变当前 layer 正确性、但必须由下一层计划或实现承接的具体事项。

### Verification

- writer 修复结果、`fix-review` 范围、artifact-specific validation、changed-file gate（适用时）、以及 `PASS` / `FAIL` / `BLOCKED` 证据。

### Readiness

- `Ready`、`Not ready` 或 `Blocked`，并用一句话说明是否可进入下一阶段或完成闭环。
