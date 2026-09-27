$skillPath = Join-Path $PSScriptRoot '..\SKILL.md'

Describe 'git-workflow 忽略内容规则' {
    It '要求被 .gitignore 排除的内容直接在当前工作目录修改和验证' {
        $content = Get-Content -Raw -Encoding utf8 $skillPath

        $content | Should Match 'git check-ignore -q'
        $content | Should Match '被 `\.gitignore` 排除的内容'
        $content | Should Match '直接在当前工作目录修改和验证'
        $content | Should Match '不新建分支、不创建 worktree'
        $content | Should Match '仅适用于 Git 跟踪的测试、源代码与文档'
    }
}

Describe 'git-workflow worktree 规则' {
    It '把 worktree 生命周期交给 Codex，并规范手动兜底命名与清理' {
        $content = Get-Content -Raw -Encoding utf8 $skillPath

        $content | Should Match 'git rev-parse --git-dir'
        $content | Should Match 'git rev-parse --git-common-dir'
        $content | Should Match '/\.codex/worktrees/'
        $content | Should Match '禁止手动 `git worktree add`'
        $content | Should Match '<仓库>\.worktrees'
        $content | Should Match 'GIT_WORKFLOW_WORKTREE_ROOT'
        $content | Should Match 'scripts/worktree\.ps1'
        $content | Should Match 'feature-login-flow'
        $content | Should Match '禁止时间戳、随机串'
        $content | Should Match 'git worktree prune'
        $content | Should Match '最多保留 1 个活动 worktree'
    }

    It '脚本路径使用 skill 相对引用，不写死安装目录' {
        $content = Get-Content -Raw -Encoding utf8 $skillPath

        $content | Should Match '<skill目录>/scripts/push_branch\.ps1'
        $content | Should Not Match '\.codex/skills/git-workflow/scripts'
    }

    It '为缺少 develop 的仓库定义轻量模式' {
        $content = Get-Content -Raw -Encoding utf8 $skillPath

        $content | Should Match '轻量模式'
        $content | Should Match '不强制 `develop` 基线'
    }
}
