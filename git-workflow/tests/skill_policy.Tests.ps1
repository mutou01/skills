$skillPath = Join-Path $PSScriptRoot '..\SKILL.md'

Describe 'branch-pr-workflow 忽略内容规则' {
    It '要求被 .gitignore 排除的内容直接在当前工作目录修改和验证' {
        $content = Get-Content -Raw -Encoding utf8 $skillPath

        $content | Should Match 'git check-ignore -q'
        $content | Should Match '被 `\.gitignore` 排除的内容'
        $content | Should Match '直接在当前工作目录修改和验证'
        $content | Should Match '不新建分支、不创建 worktree'
        $content | Should Match '仅适用于 Git 跟踪的测试、源代码与文档'
    }
}
