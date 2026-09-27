#!/usr/bin/env bash
# 创建或移除规范化 worktree：根目录 <仓库>.worktrees，目录名等于分支名把 / 替换为 -。
set -euo pipefail

ACTION=""
BRANCH=""
REPOSITORY_PATH="$(pwd)"
BASE=""
WORKTREE_ROOT=""
FORCE=0

usage() {
    cat <<'EOF'
用法:
  worktree.sh --action New    --branch <分支> [--base <基线>] [--repository-path <路径>] [--worktree-root <根>]
  worktree.sh --action Remove --branch <分支> [--repository-path <路径>] [--worktree-root <根>] [--force]
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --action) ACTION="${2:-}"; shift 2 ;;
        --branch) BRANCH="${2:-}"; shift 2 ;;
        --repository-path) REPOSITORY_PATH="${2:-}"; shift 2 ;;
        --base) BASE="${2:-}"; shift 2 ;;
        --worktree-root) WORKTREE_ROOT="${2:-}"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ "$ACTION" != "New" ] && [ "$ACTION" != "Remove" ]; then
    echo "--action 必须是 New 或 Remove。" >&2
    exit 2
fi
if [ -z "$BRANCH" ]; then
    echo "缺少 --branch。" >&2
    exit 2
fi
if ! printf '%s' "$BRANCH" | grep -Eq '^(feature|bugfix|hotfix|release)/[a-z0-9]+([.-][a-z0-9]+)*$'; then
    echo "分支不符合短期分支命名规范: $BRANCH" >&2
    exit 1
fi

git_in() { git -C "$REPOSITORY_PATH" "$@"; }

repo_root="$(git_in rev-parse --show-toplevel)"
repo_name="$(basename "$repo_root")"
worktree_name="${BRANCH//\//-}"

if [ -z "$WORKTREE_ROOT" ]; then
    WORKTREE_ROOT="${GIT_WORKFLOW_WORKTREE_ROOT:-}"
fi
if [ -z "$WORKTREE_ROOT" ]; then
    WORKTREE_ROOT="$(dirname "$repo_root")/$repo_name.worktrees"
fi
target="$WORKTREE_ROOT/$worktree_name"

resolve_path() {
    case "$1" in
        /*|[A-Za-z]:[/\\]*) (cd "$1" 2>/dev/null && pwd -P) ;;
        *) (cd "$REPOSITORY_PATH/$1" 2>/dev/null && pwd -P) ;;
    esac
}

case "$ACTION" in
    New)
        git_dir="$(resolve_path "$(git_in rev-parse --git-dir)")"
        common_dir="$(resolve_path "$(git_in rev-parse --git-common-dir)")"
        if [ "$git_dir" != "$common_dir" ]; then
            echo "当前已处于 linked worktree，禁止嵌套创建；请就地创建短期分支。" >&2
            exit 1
        fi
        if [ -e "$target" ]; then
            echo "worktree 目标路径已存在: $target" >&2
            exit 1
        fi
        if [ -z "$BASE" ]; then
            case "$BRANCH" in
                feature/*|bugfix/*) BASE="develop" ;;
                *)
                    echo "hotfix/release 必须显式指定 --base（生产分支）。" >&2
                    exit 1
                    ;;
            esac
        fi
        if git_in show-ref --verify --quiet "refs/heads/$BRANCH"; then
            git_in worktree add "$target" "$BRANCH" >/dev/null
        else
            git_in worktree add -b "$BRANCH" "$target" "$BASE" >/dev/null
        fi
        printf 'action=%s\nbranch=%s\nbase=%s\npath=%s\nstatus=%s\n' "New" "$BRANCH" "$BASE" "$target" "worktree 已创建"
        ;;
    Remove)
        if [ ! -e "$target" ]; then
            echo "worktree 不存在: $target" >&2
            exit 1
        fi
        dirty="$(git -C "$target" status --porcelain)"
        if [ -n "$dirty" ] && [ "$FORCE" -ne 1 ]; then
            echo "worktree 存在未提交改动，拒绝自动删除；确认后使用 --force: $target" >&2
            exit 1
        fi
        if [ "$FORCE" -eq 1 ]; then
            git_in worktree remove --force "$target" >/dev/null
        else
            git_in worktree remove "$target" >/dev/null
        fi
        git_in worktree prune >/dev/null
        printf 'action=%s\nbranch=%s\npath=%s\nstatus=%s\n' "Remove" "$BRANCH" "$target" "worktree 已移除"
        ;;
esac
