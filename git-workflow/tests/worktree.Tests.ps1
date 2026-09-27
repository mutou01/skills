$scriptPath = Join-Path $PSScriptRoot '..\scripts\worktree.ps1'

function Invoke-TestGit {
    param(
        [string]$RepositoryPath,
        [string[]]$Arguments
    )

    $output = & git -C $RepositoryPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') 失败: $output"
    }
    return $output
}

function New-TestRepository {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("git-workflow-wt-$([guid]::NewGuid().ToString('N'))")
    $remote = Join-Path $root 'remote.git'
    $seed = Join-Path $root 'seed'
    $work = Join-Path $root 'work'

    New-Item -ItemType Directory -Path $root | Out-Null
    & git init --bare $remote 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '无法创建测试远端仓库。' }

    & git init $seed 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '无法创建测试种子仓库。' }
    Invoke-TestGit $seed @('config', 'user.name', 'Test User') | Out-Null
    Invoke-TestGit $seed @('config', 'user.email', 'test@example.com') | Out-Null
    Invoke-TestGit $seed @('checkout', '-b', 'develop') | Out-Null
    Set-Content -Encoding utf8 -Path (Join-Path $seed 'shared.txt') -Value 'base'
    Invoke-TestGit $seed @('add', 'shared.txt') | Out-Null
    Invoke-TestGit $seed @('commit', '-m', 'core:初始化测试仓库') | Out-Null
    Invoke-TestGit $seed @('remote', 'add', 'origin', $remote) | Out-Null
    Invoke-TestGit $seed @('push', '-u', 'origin', 'develop') | Out-Null
    Invoke-TestGit $remote @('symbolic-ref', 'HEAD', 'refs/heads/develop') | Out-Null

    & git clone $remote $work 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '无法克隆测试工作仓库。' }
    Invoke-TestGit $work @('config', 'user.name', 'Test User') | Out-Null
    Invoke-TestGit $work @('config', 'user.email', 'test@example.com') | Out-Null

    [pscustomobject]@{
        Root = $root
        Remote = $remote
        Seed = $seed
        Work = $work
    }
}

Describe 'worktree.ps1' {
    $repository = $null

    AfterEach {
        if ($repository -and (Test-Path $repository.Root)) {
            Remove-Item -Recurse -Force $repository.Root
        }
        $repository = $null
    }

    It '在 <仓库>.worktrees 下按分支名创建 worktree' {
        $repository = New-TestRepository
        $root = Join-Path $repository.Root 'tree-root'
        $expected = Join-Path $root 'feature-login-flow'

        $result = & $scriptPath -Action New -Branch 'feature/login-flow' -RepositoryPath $repository.Work -WorktreeRoot $root

        $result.Path | Should Be $expected
        Test-Path $expected | Should Be $true
        Invoke-TestGit $repository.Work @('show-ref', '--verify', 'refs/heads/feature/login-flow') | Out-Null
    }

    It '默认根为仓库同级 <仓库>.worktrees' {
        $repository = New-TestRepository
        $repoName = Split-Path $repository.Work -Leaf
        $expected = Join-Path (Join-Path $repository.Root "$repoName.worktrees") 'bugfix-fix-typo'

        $result = & $scriptPath -Action New -Branch 'bugfix/fix-typo' -RepositoryPath $repository.Work

        $result.Path | Should Be $expected
        Test-Path $expected | Should Be $true
    }

    It 'Remove 删除 worktree 并执行 prune' {
        $repository = New-TestRepository
        $root = Join-Path $repository.Root 'tree-root'
        $target = (& $scriptPath -Action New -Branch 'feature/cleanup' -RepositoryPath $repository.Work -WorktreeRoot $root).Path

        $result = & $scriptPath -Action Remove -Branch 'feature/cleanup' -RepositoryPath $repository.Work -WorktreeRoot $root

        $result.Status | Should Be 'worktree 已移除'
        Test-Path $target | Should Be $false
        $list = Invoke-TestGit $repository.Work @('worktree', 'list')
        ($list -join "`n") | Should Not Match ([regex]::Escape($target))
    }

    It '拒绝不合规的分支名' {
        $repository = New-TestRepository

        { & $scriptPath -Action New -Branch 'Feature/Bad_Name' -RepositoryPath $repository.Work } | Should Throw '命名规范'
    }

    It '在 linked worktree 内拒绝嵌套创建' {
        $repository = New-TestRepository
        $root = Join-Path $repository.Root 'tree-root'
        $outer = (& $scriptPath -Action New -Branch 'feature/outer' -RepositoryPath $repository.Work -WorktreeRoot $root).Path

        { & $scriptPath -Action New -Branch 'feature/inner' -RepositoryPath $outer -WorktreeRoot $root } | Should Throw '禁止嵌套'
    }

    It 'Remove 遇到未提交改动时拒绝，-Force 可强制删除' {
        $repository = New-TestRepository
        $root = Join-Path $repository.Root 'tree-root'
        $target = (& $scriptPath -Action New -Branch 'feature/dirty' -RepositoryPath $repository.Work -WorktreeRoot $root).Path
        Set-Content -Encoding utf8 -Path (Join-Path $target 'dirty.txt') -Value 'dirty'

        { & $scriptPath -Action Remove -Branch 'feature/dirty' -RepositoryPath $repository.Work -WorktreeRoot $root } | Should Throw '未提交改动'
        Test-Path $target | Should Be $true

        & $scriptPath -Action Remove -Branch 'feature/dirty' -RepositoryPath $repository.Work -WorktreeRoot $root -Force | Out-Null
        Test-Path $target | Should Be $false
    }
}
