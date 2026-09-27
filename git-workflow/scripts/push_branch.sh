#!/usr/bin/env bash
# 自动推送短期分支：feature/bugfix 先同步远端 develop，再执行普通推送。
set -euo pipefail

BRANCH=""
REMOTE="origin"
REPOSITORY_PATH="$(pwd)"
AUTHORIZED=0

usage() {
    cat <<'EOF'
用法: push_branch.sh --branch <分支> [--remote origin] [--repository-path <路径>] --authorized
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --branch) BRANCH="${2:-}"; shift 2 ;;
        --remote) REMOTE="${2:-}"; shift 2 ;;
        --repository-path) REPOSITORY_PATH="${2:-}"; shift 2 ;;
        --authorized) AUTHORIZED=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$BRANCH" ]; then
    echo "缺少 --branch。" >&2
    exit 2
fi
if [ "$AUTHORIZED" -ne 1 ]; then
    echo "自动推送需要用户明确授权，请传入 --authorized。" >&2
    exit 2
fi
case "$BRANCH" in
    main|master|develop)
        echo "禁止推送受保护分支: $BRANCH" >&2
        exit 1
        ;;
esac
if ! printf '%s' "$BRANCH" | grep -Eq '^(feature|bugfix|hotfix|release)/[a-z0-9]+([.-][a-z0-9]+)*$'; then
    echo "分支不符合短期分支命名规范: $BRANCH" >&2
    exit 1
fi

git_in() { git -C "$REPOSITORY_PATH" "$@"; }

current_branch="$(git_in branch --show-current)"
if [ -z "$current_branch" ]; then
    echo "当前处于 detached HEAD，不能自动推送。" >&2
    exit 1
fi
if [ "$current_branch" != "$BRANCH" ]; then
    echo "当前分支为 $current_branch，拒绝推送指定分支 $BRANCH。" >&2
    exit 1
fi

git_in remote get-url "$REMOTE" >/dev/null
git_in rev-parse --verify HEAD >/dev/null

case "$BRANCH" in
    feature/*|bugfix/*)
        develop_ref="$REMOTE/develop"
        git_in fetch "$REMOTE" "develop:refs/remotes/$develop_ref" >/dev/null
        if ! git_in merge --no-edit "$develop_ref" >/dev/null; then
            conflicted="$(git_in diff --name-only --diff-filter=U | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
            if [ -n "$conflicted" ]; then
                echo "同步 $develop_ref 时发生冲突：$conflicted。已保留合并现场，请申请人工接入处理后再重新推送。" >&2
                exit 1
            fi
            echo "同步 $develop_ref 失败。" >&2
            exit 1
        fi
        ;;
esac

git_in push --set-upstream "$REMOTE" "$BRANCH" >/dev/null
commit="$(git_in rev-parse --short HEAD)"
printf 'branch=%s\nremote=%s\ncommit=%s\nstatus=%s\n' "$BRANCH" "$REMOTE" "$commit" "推送成功"
