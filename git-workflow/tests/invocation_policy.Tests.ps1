$skillPath = Join-Path $PSScriptRoot '..\SKILL.md'
$metadataPath = Join-Path $PSScriptRoot '..\agents\openai.yaml'

Describe 'branch-pr-workflow 显式调用策略' {
    It '默认提示明确要求使用 $branch-pr-workflow 且禁止隐式调用' {
        $metadata = Get-Content -Raw -Encoding utf8 $metadataPath
        $skill = Get-Content -Raw -Encoding utf8 $skillPath

        $metadata | Should Match 'allow_implicit_invocation:\s*false'
        $metadata | Should Match '\$branch-pr-workflow'
        $skill | Should Match '明确输入 `\$branch-pr-workflow`'
    }
}
