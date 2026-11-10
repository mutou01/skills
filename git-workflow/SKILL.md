---
name: git-workflow
description: 固化并执行分支、Pull Request、合并、发布、hotfix 与同步清理规范。任何仓库追踪文件修改前必须调用；也用于创建或审查分支/PR、完整或选择性发布、线上紧急修复，以及需要验证分支保护、AI 协作边界和人工审核要求的任务。
---

# 分支与 PR 协作流程

## 显式调用

仅在用户明确输入 `$git-workflow` 时启用本 skill；未明确调用时不自动注入本 skill 的规则。

## 适用范围

- 完整模式：同时具备 `develop` 与生产分支（`main`/`master`）的业务仓库，执行全部分支、PR、发布与 worktree 规则。
- 轻量模式：不具备该分支模型的仓库（例如本 skill 自身源码仓库，只有单一默认分支）。此类仓库只执行提交消息、授权、worktree 命名与清理规则，不强制 `develop` 基线，也不因缺少 `develop` 阻塞。

## 修改前强制门禁

本节适用于任何会修改仓库追踪文件的任务，包括补测试、生成文件、格式化、暂存和提交。先读取仓库根目录和目标路径最近的 `AGENTS.md`，再对每个目标执行 `git check-ignore -q -- <目标路径>`。被 `.gitignore` 排除的内容直接在当前工作目录修改和验证，不新建分支、不创建 worktree，也不得用 `git add -f` 纳入版本控制。

首次修改追踪文件前，按顺序执行并记录工作区预检：

```bash
git rev-parse --show-toplevel
git branch --show-current
git status --short
git remote -v
```

分支关卡仅适用于 Git 跟踪的测试、源代码与文档。完整模式下，检查当前分支和工作区差异后，按“分支定位与命名”核实当前短期分支及其基线；不得直接在 `develop`、`main` 或 `master` 上修改。

预检未完成、仓库边界不清或分支规则不满足时，不得修改；先报告发现，等待用户决定分支或范围。若有无关未提交改动或分支基线不符，须按“Worktree 归属、命名与清理”隔离后再修改；只迁移本次目标文件，无关文件留在原 worktree，不得暂存、提交、移动或格式化。

首次修改前按“实现与测试闭环”明确验收条件；只改一处、先补测试或已读过 `AGENTS.md` 都不能跳过门禁。修改本技能也遵守同一门禁，并通过测试验证规则文本和默认提示。

## 分支定位与命名

- 长期分支为 `main` 与 `develop`；仓库使用 `master` 时，将 `master` 兼容识别为生产分支别名，但仍要求存在 `develop`。
- `feature/<short-description>` 和 `bugfix/<short-description>` 从 `develop` 创建并合入 `develop`。
- `hotfix/<short-description>` 从生产分支（`main` 或兼容的 `master`）创建，修复后合入生产分支，并立即将同一修复同步到 `develop`。
- `release/<version>` 仅用于选择性发布或版本冻结，从生产分支创建，完成后删除。
- 名称只使用英文小写、数字和连字符；不使用空格、下划线或个人姓名，能用时加入 Issue/Jira/Linear 编号。
- 一个短期分支只服务一个独立功能或问题；一个独立变更对应一个 PR。
- 缺少 `develop`、生产分支识别不清或分支基线不符合规范时，停止并报告阻塞；不得擅自创建或迁移长期分支。

## Worktree 归属、命名与清理

- 先判断是否确需新建。`git rev-parse --git-dir` 与 `git rev-parse --git-common-dir` 解析为绝对路径后不同，表示已处于 linked worktree；符合修改预检时就地复用，需要时创建获授权的短期分支。禁止从 linked worktree 嵌套创建。
- 确需新建时，优先级为：**用户明确指定的新建 worktree 规则 > 编码代理原生的新建 worktree 规则 > 本技能的兜底规则**。团队或公司规范以用户明确提供或指定的内容为准；通常没有此类覆盖，无需例行询问。若创建入口无法满足已明确的规则，停止并说明冲突。
- 用户指定的规则只覆盖其明确规定的事项，且不得绕过运行环境的强制限制。其余按当前编码代理可核实的原生规则处理，例如使用 Codex 的 worktree 入口。由编码代理管理的 worktree 按其规则创建、命名和回收，禁止手动 `git worktree add` 或用本技能脚本替代。原生规则适用但入口不可用或创建失败时，停止新建并报告原因，不降级为手动兜底。
- 只有没有用户规则覆盖创建方式、且当前编码代理没有适用的原生规则时，才用 `scripts/worktree.sh` 创建 worktree。以下目录、命名和清理要求只适用于本技能的手动兜底；禁止直接执行 `git worktree add` 或 `git worktree remove`。
- 上述优先级只处理新建 worktree 及其归属，不改变分支基线、分支命名或操作授权。原生入口若产生临时分支或分离 HEAD，仍须通过修改前的分支关卡。
- 手动 worktree 根目录为仓库同级 `<仓库>.worktrees`，可用 `GIT_WORKFLOW_WORKTREE_ROOT` 环境变量或 `--worktree-root` 参数覆盖。
- worktree 目录名等于分支名把 `/` 替换为 `-`，即 `<type>-<short-description>`，例如 `feature/login-flow` 对应 `<仓库>.worktrees/feature-login-flow`。禁止时间戳、随机串、中文、空格、下划线和个人姓名。
- 清理：合并后必须删除对应 worktree 并执行 `git worktree prune`；同一时间最多保留 1 个活动 worktree；不在 worktree 内重复安装依赖，除非本次任务确需运行测试。删除含未提交改动的 worktree 必须显式 `--force`。

```bash
bash "<skill目录>/scripts/worktree.sh" --action New --branch "feature/<short-description>" --repository-path "<仓库路径>"
bash "<skill目录>/scripts/worktree.sh" --action Remove --branch "feature/<short-description>" --repository-path "<仓库路径>"
```

## 保护与授权

- `main`、`master`、`develop` 均禁止直接 push、强制推送、删除或绕过 PR 修改。
- 所有创建分支、提交、推送、合并、删除短期分支和线上 PR 操作，都必须得到用户明确授权；没有授权时只做检查、建议和内容准备。
- 合并后仅可删除已合并且获得授权的 `feature/*`、`bugfix/*`、`hotfix/*`、临时 `release/*`；长期分支永不删除。
- 禁止通过仓库外手工修改生产代码绕过记录。若紧急人工变更已经发生，必须立即补齐 `hotfix/*` PR 和同步记录。

## 提交消息

- 为人工或 AI 编写的业务提交使用固定格式：`<type>:<简短的中文描述>`；`type` 与描述之间不加空格。
- 仅使用以下 `type`：`feat`、`fix`、`core`、`docs`、`test`、`chore`。
- 使用单行、简短的中文描述，只说明一个独立改动；末尾中文分号 `；` 可保留但不强制，避免用多个分号拼接多个独立改动。
- 提交前按格式自检。例如：`feat:新增提现配置筛选`、`fix:修复订单状态更新`、`core:调整数据库装配`、`docs:补充部署说明`、`test:覆盖登录失败场景`、`chore:更新本地开发依赖`。
- Git 平台自动生成的 Merge Commit，以及推送前同步 `develop` 时由 Git 自动生成的 Merge Commit，不适用本规则。

## 自动推送

只有用户明确授权推送当前短期分支且本地验证通过后，agent 才可自动执行 `scripts/push_branch.sh`。可接受的自然语言授权例如：“允许自动推送当前 feature 分支”或“本次修复验证通过后自动推送”。agent 必须在执行报告中记录对应授权和实际推送结果。

`--authorized` 不是 Token、密钥或平台权限，也不需要申请或生成；它是 agent 在已经核实用户明确授权后传入的本地确认开关。脚本只允许推送当前检出的 `feature/*`、`bugfix/*`、`hotfix/*` 或 `release/*` 分支；拒绝 `main`、`master`、`develop`、分离 HEAD、命名不合规分支及与当前分支不一致的推送目标。

推送 `feature/*`、`bugfix/*` 前，脚本先获取并合并最新的 `<remote>/develop`；`hotfix/*`、`release/*` 按生产分支基线，不合并 `develop`。远端由 `--remote` 指定，默认 `origin`；脚本执行普通 `git push --set-upstream <remote> <branch>`，不支持强推。

同步发生冲突时，立即停止且不推送，不执行 `git merge --abort`；保留冲突文件和 Git 合并状态，明确申请人工接入解决冲突。人工完成合并后重新执行推送命令。该同步不改变完成开发任务后的自动提交条件、推送授权条件或业务提交消息规范。

```bash
bash "<skill目录>/scripts/push_branch.sh" \
  --repository-path "<仓库路径>" --branch "feature/<short-description>" --authorized
```

推送成功仅表示远端接受了当前提交，不等于 CI 通过、PR 已创建、人工审核完成或代码已合并；完成报告必须分别说明这些状态。

## 实现与测试闭环

1. 定位：按修改前门禁确认仓库状态，读取相关 README、接口、调用链和测试，明确影响模块。
2. 设计：修改前明确需求范围和可验证的验收条件；有关键歧义就停下来请求确认。
3. 测试先行：先用失败测试覆盖新行为或复现缺陷，再只改必要文件使测试通过，保留他人改动；不得为通过 CI 而删除或跳过测试、降低校验。
4. 验证：运行目标模块要求的测试、类型检查、Lint、构建或真实请求；接口、命令及验证结论以实际证据为准。
5. 对抗性审查：检查回归风险、未覆盖路径、边界输入、并发与数据一致性、鉴权与权限、支付与部署影响、敏感信息泄露和不可逆操作。
6. 报告：列出变更、实际命令与结果、风险/未验证项、主要文件和后续人工动作。

## PR 与合并

创建或审查 PR 前确认：一个独立变更、说明和测试结果清晰、CI 通过、无冲突、无未解决评论，并完成所需审核。

- `feature/*`、`bugfix/*` 合入 `develop` 使用 Squash Merge，使一个 PR 对应一个完整提交。
- `develop` 完整发布到生产分支，或 `release/*` 发布到生产分支，使用普通 Merge Commit，保留长期分支关系。
- 选择性发布只 cherry-pick 已确认的对应 PR 的 Squash Commit，并记录原 PR 编号；不要挑选零散提交或 Merge Commit。
- 未完成功能使用 Draft PR 或默认关闭的 Feature Flag；只有不影响现有流程且通过 CI 的代码才可提前合并。

本机没有已登录且可用的 PR 客户端时，生成 PR 标题、正文、目标分支、变更摘要和验证证据后停止，并明确写出“等待人工创建 PR”；不得声称 PR 已创建、已审核或已合并。

## 发布与同步

- 完整发布：`develop` 验证完成后创建生产发布 PR，人工最终确认后合入 `main` 或 `master`，按项目需要打 Tag 和部署。
- 选择性发布：从生产分支创建 `release/<version>`，按“PR 与合并”的规则挑选提交，重新执行构建、测试和依赖检查，再通过 PR 合入生产分支并删除 release 分支。依赖无法安全拆分时整体延期，优先考虑 Feature Flag。
- 紧急修复：按“分支定位与命名”的 `hotfix/*` 路径，通过 PR 合入生产分支并完成同步。
- 只有生产分支含有 `develop` 未包含的提交（hotfix、选择性发布后的额外修复或紧急人工变更）时才创建同步 PR；完整 `develop` → 生产发布不重复同步。

## AI 与人工审核边界

AI 可以创建分支、提交代码、编写 PR 说明、运行验证和辅助 Review，但不能把 AI Review 当成人工 Approval，也不能绕过失败 CI、分支保护或安全要求。

以下改动必须人工审核后才能合并或发布：身份认证、权限、敏感数据、数据库迁移与数据修复、支付/计费/额度、密钥、生产配置、基础设施、删除数据及其他不可逆操作。

## 隔离演练

需要演练流程时，不得在用户的实际仓库、真实远端或受保护分支上模拟。创建唯一的临时仓库和本地 `bare remote`，使用 `git init --bare` 搭建隔离远端；只在明确创建的临时目录内写入演练文件，并在演练结束后清理该目录。

演练必须执行真实 Git 命令：从 `develop` 创建 `feature/*` 或 `bugfix/*`，先让测试失败，再实现最小修改使测试通过，执行 `git add`、`git commit` 与 `git push -u origin <short-lived-branch>`。记录每一步的实际分支、提交 SHA、推送结果和测试结果。

本地 bare remote 上的推送只证明 Git 命令可执行，不代表已验证真实 PR、CI、人工审核、分支保护或合并。PR 客户端不可用的情形按“PR 与合并”处理。

## 完成判定

只有在实际验证证据齐全、保护规则未被绕过、所需人工审核已完成、PR 状态真实可核查且短期分支清理得到授权后，才报告流程完成。任何未验证项、阻塞项或等待人工创建 PR 都必须明确列出。
