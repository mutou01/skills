#!/usr/bin/env bash
# 跨平台（macOS / Windows Git Bash / Linux）测试入口：bash tests/run.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$TESTS_DIR/.." && pwd)"
PUSH="$SKILL_DIR/scripts/push_branch.sh"
WORKTREE="$SKILL_DIR/scripts/worktree.sh"
SKILL_MD="$SKILL_DIR/SKILL.md"
METADATA="$SKILL_DIR/agents/openai.yaml"

PASS=0
FAIL=0
CLEANUP_DIRS=""
trap 'if [ -n "${CLEANUP_DIRS:-}" ]; then rm -rf $CLEANUP_DIRS; fi' EXIT

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "    FAIL: $1"; }
section() { echo "== $1 =="; }

assert_eq() {
    if [ "$1" = "$2" ]; then ok; else bad "$3 (期望 '$2'，实际 '$1')"; fi
}
assert_contains() {
    case "$1" in *"$2"*) ok ;; *) bad "$3 (缺少 '$2')" ;; esac
}
assert_not_contains() {
    case "$1" in *"$2"*) bad "$3 (不应包含 '$2')" ;; *) ok ;; esac
}
assert_file_exists() { if [ -e "$1" ]; then ok; else bad "$2 (不存在: $1)"; fi; }
assert_file_absent() { if [ -e "$1" ]; then bad "$2 (仍存在: $1)"; else ok; fi; }
assert_git_ok() { if git -C "$1" "${@:2}" >/dev/null 2>&1; then ok; else bad "git ${*:2} 应成功"; fi; }
assert_git_fail() { if git -C "$1" "${@:2}" >/dev/null 2>&1; then bad "git ${*:2} 应失败"; else ok; fi; }

TEST_ROOT=""
TEST_REMOTE=""
TEST_SEED=""
TEST_WORK=""

new_repo() {
    local root remote seed work
    root="$(mktemp -d)"
    CLEANUP_DIRS="$CLEANUP_DIRS $root"
    remote="$root/remote.git"
    seed="$root/seed"
    work="$root/work"

    git init --bare -q "$remote"
    git init -q "$seed"
    git -C "$seed" config user.name "Test User"
    git -C "$seed" config user.email "test@example.com"
    git -C "$seed" checkout -q -b develop
    printf 'base' > "$seed/shared.txt"
    git -C "$seed" add shared.txt
    git -C "$seed" commit -q -m "core:初始化测试仓库"
    git -C "$seed" remote add origin "$remote"
    git -C "$seed" push -q -u origin develop
    git -C "$remote" symbolic-ref HEAD refs/heads/develop

    git clone -q "$remote" "$work"
    git -C "$work" config user.name "Test User"
    git -C "$work" config user.email "test@example.com"

    TEST_ROOT="$root"
    TEST_REMOTE="$remote"
    TEST_SEED="$seed"
    TEST_WORK="$work"
}

seed_develop_commit() {
    local file="$1" content="$2"
    printf '%s' "$content" > "$TEST_SEED/$file"
    git -C "$TEST_SEED" add "$file"
    git -C "$TEST_SEED" commit -q -m "feat:更新开发分支"
    git -C "$TEST_SEED" push -q origin develop
}

# ---------------------------------------------------------------- push_branch

section "push_branch.sh"

new_repo
git -C "$TEST_WORK" checkout -q -b feature/sync-develop
printf 'feature' > "$TEST_WORK/feature.txt"
git -C "$TEST_WORK" add feature.txt
git -C "$TEST_WORK" commit -q -m "feat:新增功能文件"
seed_develop_commit develop.txt develop

out="$(bash "$PUSH" --branch feature/sync-develop --repository-path "$TEST_WORK" --authorized 2>&1)"
assert_eq "$?" "0" "推送退出码应为 0"
assert_contains "$out" "推送成功" "应报告推送成功"
assert_git_ok "$TEST_WORK" merge-base --is-ancestor origin/develop HEAD
assert_git_ok "$TEST_REMOTE" merge-base --is-ancestor refs/heads/develop refs/heads/feature/sync-develop

new_repo
git -C "$TEST_WORK" checkout -q -b feature/conflict-develop
printf 'feature' > "$TEST_WORK/shared.txt"
git -C "$TEST_WORK" add shared.txt
git -C "$TEST_WORK" commit -q -m "feat:修改共享文件"
seed_develop_commit shared.txt develop

out="$(bash "$PUSH" --branch feature/conflict-develop --repository-path "$TEST_WORK" --authorized 2>&1)"
assert_eq "$?" "1" "冲突时应返回非零"
assert_contains "$out" "请申请人工接入" "应提示人工处理冲突"
assert_git_ok "$TEST_WORK" rev-parse --verify MERGE_HEAD
assert_git_fail "$TEST_REMOTE" show-ref --verify --quiet refs/heads/feature/conflict-develop

for branch in hotfix/skip-develop release/1.0.0; do
    new_repo
    git -C "$TEST_WORK" checkout -q -b "$branch"
    printf 'x' > "$TEST_WORK/${branch%%/*}.txt"
    git -C "$TEST_WORK" add .
    git -C "$TEST_WORK" commit -q -m "fix:准备推送分支"
    seed_develop_commit develop.txt "$branch"

    out="$(bash "$PUSH" --branch "$branch" --repository-path "$TEST_WORK" --authorized 2>&1)"
    assert_eq "$?" "0" "$branch 推送退出码应为 0"
    assert_git_fail "$TEST_REMOTE" merge-base --is-ancestor refs/heads/develop "refs/heads/$branch"
done

# ------------------------------------------------------------------- worktree

section "worktree.sh"

new_repo
wt_root="$TEST_ROOT/tree-root"
out="$(bash "$WORKTREE" --action New --branch feature/login-flow --repository-path "$TEST_WORK" --worktree-root "$wt_root" 2>&1)"
assert_eq "$?" "0" "创建 worktree 退出码应为 0"
assert_contains "$out" "worktree 已创建" "应报告创建成功"
assert_contains "$out" "path=$wt_root/feature-login-flow" "路径应为 <根>/<分支slug>"
assert_file_exists "$wt_root/feature-login-flow" "worktree 目录应存在"
assert_git_ok "$TEST_WORK" show-ref --verify --quiet refs/heads/feature/login-flow

new_repo
repo_root="$(git -C "$TEST_WORK" rev-parse --show-toplevel)"
repo_name="$(basename "$repo_root")"
default_target="$(dirname "$repo_root")/$repo_name.worktrees/bugfix-fix-typo"
out="$(bash "$WORKTREE" --action New --branch bugfix/fix-typo --repository-path "$TEST_WORK" 2>&1)"
assert_contains "$out" "path=$default_target" "默认根应为仓库同级 <仓库>.worktrees"
assert_file_exists "$default_target" "默认根下应创建 worktree"

new_repo
wt_root="$TEST_ROOT/tree-root"
bash "$WORKTREE" --action New --branch feature/cleanup --repository-path "$TEST_WORK" --worktree-root "$wt_root" >/dev/null
out="$(bash "$WORKTREE" --action Remove --branch feature/cleanup --repository-path "$TEST_WORK" --worktree-root "$wt_root" 2>&1)"
assert_eq "$?" "0" "移除 worktree 退出码应为 0"
assert_contains "$out" "worktree 已移除" "应报告移除成功"
assert_file_absent "$wt_root/feature-cleanup" "worktree 目录应被删除"
assert_not_contains "$(git -C "$TEST_WORK" worktree list)" "$wt_root/feature-cleanup" "worktree list 不应再包含"

new_repo
out="$(bash "$WORKTREE" --action New --branch Feature/Bad_Name --repository-path "$TEST_WORK" 2>&1)"
assert_eq "$?" "1" "不合规分支名应被拒绝"
assert_contains "$out" "命名规范" "应提示命名规范"

new_repo
wt_root="$TEST_ROOT/tree-root"
bash "$WORKTREE" --action New --branch feature/outer --repository-path "$TEST_WORK" --worktree-root "$wt_root" >/dev/null
out="$(bash "$WORKTREE" --action New --branch feature/inner --repository-path "$wt_root/feature-outer" --worktree-root "$wt_root" 2>&1)"
assert_eq "$?" "1" "linked worktree 内应拒绝嵌套"
assert_contains "$out" "禁止嵌套" "应提示禁止嵌套"

new_repo
wt_root="$TEST_ROOT/tree-root"
bash "$WORKTREE" --action New --branch feature/dirty --repository-path "$TEST_WORK" --worktree-root "$wt_root" >/dev/null
printf 'dirty' > "$wt_root/feature-dirty/dirty.txt"
out="$(bash "$WORKTREE" --action Remove --branch feature/dirty --repository-path "$TEST_WORK" --worktree-root "$wt_root" 2>&1)"
assert_eq "$?" "1" "脏 worktree 应拒绝删除"
assert_contains "$out" "未提交改动" "应提示未提交改动"
assert_file_exists "$wt_root/feature-dirty" "拒绝后目录应保留"
bash "$WORKTREE" --action Remove --branch feature/dirty --repository-path "$TEST_WORK" --worktree-root "$wt_root" --force >/dev/null
assert_file_absent "$wt_root/feature-dirty" "--force 后应删除"

# -------------------------------------------------------------------- policy

section "policy"

content="$(cat "$SKILL_MD")"
metadata="$(cat "$METADATA")"

assert_contains "$content" 'git check-ignore -q' "SKILL.md 应含 gitignore 预检"
assert_contains "$content" '被 `.gitignore` 排除的内容' "SKILL.md 应含 gitignore 规则"
assert_contains "$content" '直接在当前工作目录修改和验证' "SKILL.md 应含就地验证规则"
assert_contains "$content" '不新建分支、不创建 worktree' "SKILL.md 应含不创建 worktree"
assert_contains "$content" '仅适用于 Git 跟踪的测试、源代码与文档' "SKILL.md 应含关卡适用范围"
assert_contains "$content" 'git rev-parse --git-dir' "SKILL.md 应含 linked worktree 检测"
assert_contains "$content" 'git rev-parse --git-common-dir' "SKILL.md 应含 linked worktree 检测"
assert_contains "$content" '/.codex/worktrees/' "SKILL.md 应含 Codex worktree 路径"
assert_contains "$content" '禁止手动 `git worktree add`' "SKILL.md 应禁止手动创建"
assert_contains "$content" '<仓库>.worktrees' "SKILL.md 应含手动根目录规则"
assert_contains "$content" 'GIT_WORKFLOW_WORKTREE_ROOT' "SKILL.md 应含根目录覆盖变量"
assert_contains "$content" 'scripts/worktree.sh' "SKILL.md 应引用 worktree.sh"
assert_contains "$content" 'scripts/push_branch.sh' "SKILL.md 应引用 push_branch.sh"
assert_contains "$content" 'feature-login-flow' "SKILL.md 应含命名示例"
assert_contains "$content" 'git worktree prune' "SKILL.md 应含 prune 清理"
assert_contains "$content" '最多保留 1 个活动 worktree' "SKILL.md 应含保留上限"
assert_contains "$content" '轻量模式' "SKILL.md 应含轻量模式"
assert_contains "$content" '不强制 `develop` 基线' "SKILL.md 应含轻量模式基线说明"
assert_not_contains "$content" '.ps1' "SKILL.md 不应再引用 ps1 脚本"

assert_contains "$metadata" 'allow_implicit_invocation: false' "openai.yaml 应禁止隐式调用"
assert_contains "$metadata" '$git-workflow' "openai.yaml 应引用 \$git-workflow"
assert_contains "$content" '明确输入 `$git-workflow`' "SKILL.md 应要求显式调用"

assert_file_exists "$PUSH" "push_branch.sh 应存在"
assert_file_exists "$WORKTREE" "worktree.sh 应存在"
assert_file_absent "$SKILL_DIR/scripts/push_branch.ps1" "push_branch.ps1 应删除"
assert_file_absent "$SKILL_DIR/scripts/worktree.ps1" "worktree.ps1 应删除"
assert_file_absent "$SKILL_DIR/tests/push_branch.Tests.ps1" "旧 ps1 测试应删除"
assert_file_absent "$SKILL_DIR/tests/worktree.Tests.ps1" "旧 ps1 测试应删除"
assert_file_absent "$SKILL_DIR/tests/skill_policy.Tests.ps1" "旧 ps1 测试应删除"
assert_file_absent "$SKILL_DIR/tests/invocation_policy.Tests.ps1" "旧 ps1 测试应删除"

# ------------------------------------------------------------------- summary

echo
echo "Passed: $PASS Failed: $FAIL"
[ "$FAIL" -eq 0 ]
