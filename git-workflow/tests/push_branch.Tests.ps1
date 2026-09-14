$scriptPath = Join-Path $PSScriptRoot '..\scripts\push_branch.ps1'

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
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("branch-pr-workflow-$([guid]::NewGuid().ToString('N'))")
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

function Add-DevelopCommit {
    param(
        [pscustomobject]$Repository,
        [string]$FileName,
        [string]$Content
    )

    Set-Content -Encoding utf8 -Path (Join-Path $Repository.Seed $FileName) -Value $Content
    Invoke-TestGit $Repository.Seed @('add', $FileName) | Out-Null
    Invoke-TestGit $Repository.Seed @('commit', '-m', 'feat:更新开发分支') | Out-Null
    Invoke-TestGit $Repository.Seed @('push', 'origin', 'develop') | Out-Null
}

Describe 'push_branch.ps1' {
    $repository = $null

    AfterEach {
        if ($repository -and (Test-Path $repository.Root)) {
            Remove-Item -Recurse -Force $repository.Root
        }
        $repository = $null
    }

    It '在推送 feature 分支前合并远端最新 develop' {
        $repository = New-TestRepository
        Invoke-TestGit $repository.Work @('checkout', '-b', 'feature/sync-develop') | Out-Null
        Set-Content -Encoding utf8 -Path (Join-Path $repository.Work 'feature.txt') -Value 'feature'
        Invoke-TestGit $repository.Work @('add', 'feature.txt') | Out-Null
        Invoke-TestGit $repository.Work @('commit', '-m', 'feat:新增功能文件') | Out-Null
        Add-DevelopCommit $repository 'develop.txt' 'develop'

        & $scriptPath -Branch 'feature/sync-develop' -RepositoryPath $repository.Work -Authorized | Out-Null

        Invoke-TestGit $repository.Work @('merge-base', '--is-ancestor', 'origin/develop', 'HEAD') | Out-Null
        Invoke-TestGit $repository.Remote @('merge-base', '--is-ancestor', 'refs/heads/develop', 'refs/heads/feature/sync-develop') | Out-Null
    }

    It '同步 develop 发生冲突时保留现场并停止推送' {
        $repository = New-TestRepository
        Invoke-TestGit $repository.Work @('checkout', '-b', 'feature/conflict-develop') | Out-Null
        Set-Content -Encoding utf8 -Path (Join-Path $repository.Work 'shared.txt') -Value 'feature'
        Invoke-TestGit $repository.Work @('add', 'shared.txt') | Out-Null
        Invoke-TestGit $repository.Work @('commit', '-m', 'feat:修改共享文件') | Out-Null
        Add-DevelopCommit $repository 'shared.txt' 'develop'

        $error = $null
        try {
            & $scriptPath -Branch 'feature/conflict-develop' -RepositoryPath $repository.Work -Authorized | Out-Null
        } catch {
            $error = $_
        }

        $error | Should Not BeNullOrEmpty
        $error.Exception.Message | Should Match '请申请人工接入'
        Invoke-TestGit $repository.Work @('rev-parse', '--verify', 'MERGE_HEAD') | Out-Null
        & git -C $repository.Remote show-ref --verify --quiet 'refs/heads/feature/conflict-develop'
        $LASTEXITCODE | Should Be 1
    }

    It '不会将 develop 合并到 hotfix 与 release 分支' {
        foreach ($branch in @('hotfix/skip-develop', 'release/1.0.0')) {
            $repository = New-TestRepository
            Invoke-TestGit $repository.Work @('checkout', '-b', $branch) | Out-Null
            Set-Content -Encoding utf8 -Path (Join-Path $repository.Work "$($branch.Split('/')[0]).txt") -Value $branch
            Invoke-TestGit $repository.Work @('add', '.') | Out-Null
            Invoke-TestGit $repository.Work @('commit', '-m', 'fix:准备推送分支') | Out-Null
            Add-DevelopCommit $repository 'develop.txt' $branch

            & $scriptPath -Branch $branch -RepositoryPath $repository.Work -Authorized | Out-Null

            & git -C $repository.Remote merge-base --is-ancestor 'refs/heads/develop' "refs/heads/$branch"
            $LASTEXITCODE | Should Be 1
            Remove-Item -Recurse -Force $repository.Root
            $repository = $null
        }
    }
}
