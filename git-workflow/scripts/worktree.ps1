[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('New', 'Remove')]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$Branch,

    [string]$RepositoryPath = (Get-Location).Path,

    [string]$Base,

    [string]$WorktreeRoot,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

if ($Branch -notmatch '^(feature|bugfix|hotfix|release)/[a-z0-9]+(?:[.-][a-z0-9]+)*$') {
    throw "分支不符合短期分支命名规范: $Branch"
}

$git = (Get-Command git -ErrorAction Stop).Source

function Invoke-Git {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = $RepositoryPath
    )

    $output = & $git -C $WorkingDirectory @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') 失败: $output"
    }
    return $output
}

function Resolve-GitPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $RepositoryPath $Path))
}

$repoRoot = (Invoke-Git @('rev-parse', '--show-toplevel')).Trim()
$repoName = Split-Path $repoRoot -Leaf
$worktreeName = $Branch -replace '/', '-'

if ([string]::IsNullOrWhiteSpace($WorktreeRoot)) {
    $WorktreeRoot = $env:GIT_WORKFLOW_WORKTREE_ROOT
}
if ([string]::IsNullOrWhiteSpace($WorktreeRoot)) {
    $WorktreeRoot = Join-Path (Split-Path $repoRoot -Parent) "$repoName.worktrees"
}
$targetPath = Join-Path $WorktreeRoot $worktreeName

function Test-LinkedWorktree {
    $gitDir = Resolve-GitPath (Invoke-Git @('rev-parse', '--git-dir')).Trim()
    $commonDir = Resolve-GitPath (Invoke-Git @('rev-parse', '--git-common-dir')).Trim()
    return ($gitDir -ne $commonDir)
}

switch ($Action) {
    'New' {
        if (Test-LinkedWorktree) {
            throw '当前已处于 linked worktree，禁止嵌套创建；请就地创建短期分支。'
        }
        if (Test-Path $targetPath) {
            throw "worktree 目标路径已存在: $targetPath"
        }
        if ([string]::IsNullOrWhiteSpace($Base)) {
            if ($Branch -match '^(feature|bugfix)/') {
                $Base = 'develop'
            } else {
                throw "hotfix/release 必须显式指定 -Base（生产分支）。"
            }
        }

        & $git -C $repoRoot show-ref --verify --quiet "refs/heads/$Branch"
        if ($LASTEXITCODE -eq 0) {
            Invoke-Git @('worktree', 'add', $targetPath, $Branch) | Out-Null
        } else {
            Invoke-Git @('worktree', 'add', '-b', $Branch, $targetPath, $Base) | Out-Null
        }

        [pscustomobject]@{
            Action = 'New'
            Branch = $Branch
            Base   = $Base
            Path   = $targetPath
            Status = 'worktree 已创建'
        }
    }
    'Remove' {
        if (-not (Test-Path $targetPath)) {
            throw "worktree 不存在: $targetPath"
        }

        $dirty = Invoke-Git @('status', '--porcelain') -WorkingDirectory $targetPath
        if ($dirty -and -not $Force) {
            throw "worktree 存在未提交改动，拒绝自动删除；确认后使用 -Force: $targetPath"
        }

        if ($Force) {
            Invoke-Git @('worktree', 'remove', '--force', $targetPath) | Out-Null
        } else {
            Invoke-Git @('worktree', 'remove', $targetPath) | Out-Null
        }
        Invoke-Git @('worktree', 'prune') | Out-Null

        [pscustomobject]@{
            Action = 'Remove'
            Branch = $Branch
            Path   = $targetPath
            Status = 'worktree 已移除'
        }
    }
}
