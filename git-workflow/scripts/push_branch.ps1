[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Branch,

    [string]$Remote = 'origin',

    [string]$RepositoryPath = (Get-Location).Path,

    [switch]$Authorized
)

$ErrorActionPreference = 'Stop'

if (-not $Authorized) {
    throw '自动推送需要用户明确授权，请传入 -Authorized。'
}

if ($Branch -in @('main', 'master', 'develop')) {
    throw "禁止推送受保护分支: $Branch"
}

if ($Branch -notmatch '^(feature|bugfix|hotfix|release)/[a-z0-9]+(?:[.-][a-z0-9]+)*$') {
    throw "分支不符合短期分支命名规范: $Branch"
}

$git = (Get-Command git -ErrorAction Stop).Source

function Invoke-Git {
    param([string[]]$Arguments)

    $output = & $git -C $RepositoryPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') 失败: $output"
    }
    return $output
}

$currentBranch = (Invoke-Git @('branch', '--show-current')).Trim()
if ([string]::IsNullOrWhiteSpace($currentBranch)) {
    throw '当前处于 detached HEAD，不能自动推送。'
}
if ($currentBranch -ne $Branch) {
    throw "当前分支为 $currentBranch，拒绝推送指定分支 $Branch。"
}

Invoke-Git @('remote', 'get-url', $Remote) | Out-Null
Invoke-Git @('rev-parse', '--verify', 'HEAD') | Out-Null

if ($Branch -match '^(feature|bugfix)/') {
    $developRef = "$Remote/develop"
    Invoke-Git @('fetch', $Remote, "develop:refs/remotes/$developRef") | Out-Null
    try {
        Invoke-Git @('merge', '--no-edit', $developRef) | Out-Null
    } catch {
        $conflictedFiles = & $git -C $RepositoryPath diff --name-only --diff-filter=U 2>$null
        if ($LASTEXITCODE -eq 0 -and $conflictedFiles) {
            $files = ($conflictedFiles | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ', '
            throw "同步 $developRef 时发生冲突：$files。已保留合并现场，请申请人工接入处理后再重新推送。"
        }
        throw
    }
}

Invoke-Git @('push', '--set-upstream', $Remote, $Branch) | Out-Null

[pscustomobject]@{
    Branch = $Branch
    Remote = $Remote
    Commit = (Invoke-Git @('rev-parse', '--short', 'HEAD')).Trim()
    Status = '推送成功'
}
