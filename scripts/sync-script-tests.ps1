param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptRoot
)

$ErrorActionPreference = "Stop"

function Assert-Contains($Text, $Expected, $Name) {
    if ($Text -notlike "*$Expected*") {
        throw "$Name failed: expected output to contain '$Expected'"
    }
}

function Assert-NotContains($Text, $Unexpected, $Name) {
    if ($Text -like "*$Unexpected*") {
        throw "$Name failed: expected output not to contain '$Unexpected'"
    }
}

function Assert-FileContains($Path, $Expected, $Name) {
    $content = Get-Content -LiteralPath $Path -Raw
    Assert-Contains $content $Expected $Name
}

function Assert-True($Condition, $Name) {
    if (-not $Condition) {
        throw "$Name failed: expected condition to be true"
    }
}

function Invoke-Git($GitArgs, $Repo) {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git @GitArgs 2>&1
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') failed in $Repo`n$output"
    }
    return $output
}

function Invoke-ScriptUnderTest($Path, $InputText = $null) {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if ($null -eq $InputText) {
            return (& powershell -NoProfile -ExecutionPolicy Bypass -File $Path 2>&1 | Out-String)
        }

        $escapedPath = $Path.Replace("'", "''")
        $escapedInput = $InputText.Replace("'", "''")
        $command = "function Read-Host { param([string]`$Prompt) '$escapedInput' }; & '$escapedPath'"
        return (& powershell -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1 | Out-String)
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function New-SyncFixture {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("new-api-sync-tests-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $root | Out-Null

    $seed = Join-Path $root "seed"
    $upstreamBare = Join-Path $root "upstream.git"
    $originBare = Join-Path $root "origin.git"
    $work = Join-Path $root "work"

    Invoke-Git -GitArgs @("init", "-b", "main", $seed) -Repo $root | Out-Null
    Invoke-Git -GitArgs @("-C", $seed, "config", "user.email", "test@example.invalid") -Repo $seed | Out-Null
    Invoke-Git -GitArgs @("-C", $seed, "config", "user.name", "Sync Test") -Repo $seed | Out-Null
    Set-Content -Path (Join-Path $seed "README.md") -Value "base" -Encoding utf8
    Invoke-Git -GitArgs @("-C", $seed, "add", "README.md") -Repo $seed | Out-Null
    Invoke-Git -GitArgs @("-C", $seed, "commit", "-m", "base") -Repo $seed | Out-Null

    Invoke-Git -GitArgs @("init", "--bare", $upstreamBare) -Repo $root | Out-Null
    Invoke-Git -GitArgs @("init", "--bare", $originBare) -Repo $root | Out-Null
    Invoke-Git -GitArgs @("-C", $seed, "remote", "add", "upstream", $upstreamBare) -Repo $seed | Out-Null
    Invoke-Git -GitArgs @("-C", $seed, "remote", "add", "origin", $originBare) -Repo $seed | Out-Null
    Invoke-Git -GitArgs @("-C", $seed, "push", "upstream", "main") -Repo $seed | Out-Null
    Invoke-Git -GitArgs @("-C", $seed, "push", "origin", "main") -Repo $seed | Out-Null
    Invoke-Git -GitArgs @("-C", $upstreamBare, "symbolic-ref", "HEAD", "refs/heads/main") -Repo $upstreamBare | Out-Null
    Invoke-Git -GitArgs @("-C", $originBare, "symbolic-ref", "HEAD", "refs/heads/main") -Repo $originBare | Out-Null

    Invoke-Git -GitArgs @("clone", $originBare, $work) -Repo $root | Out-Null
    Invoke-Git -GitArgs @("-C", $work, "checkout", "-b", "dev") -Repo $work | Out-Null
    Invoke-Git -GitArgs @("-C", $work, "remote", "add", "upstream", $upstreamBare) -Repo $work | Out-Null

    Set-Content -Path (Join-Path $seed "README.md") -Value "upstream" -Encoding utf8
    Invoke-Git -GitArgs @("-C", $seed, "commit", "-am", "upstream") -Repo $seed | Out-Null
    Invoke-Git -GitArgs @("-C", $seed, "push", "upstream", "main") -Repo $seed | Out-Null

    [pscustomobject]@{
        Root = $root
        Work = $work
        OriginBare = $originBare
    }
}

function Test-SyncDevExitsWhenUserDeclinesDevCheckout {
    $fixture = New-SyncFixture
    try {
        Push-Location $fixture.Work
        Invoke-Git -GitArgs @("checkout", "-b", "feature") -Repo $fixture.Work | Out-Null
        $output = Invoke-ScriptUnderTest -Path (Join-Path $ScriptRoot "sync-dev.ps1") -InputText "n"
        $branch = Invoke-Git -GitArgs @("branch", "--show-current") -Repo $fixture.Work
        Pop-Location

        Assert-Contains $branch "feature" "sync-dev branch"
        Assert-NotContains $output "git merge upstream/main" "sync-dev decline"
    } finally {
        if ((Get-Location).Path -eq $fixture.Work) { Pop-Location }
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

function Test-SyncDevRunsNoCommitMergeForManualReview {
    $fixture = New-SyncFixture
    try {
        Push-Location $fixture.Work
        $headBefore = Invoke-Git -GitArgs @("rev-parse", "HEAD") -Repo $fixture.Work
        $output = Invoke-ScriptUnderTest -Path (Join-Path $ScriptRoot "sync-dev.ps1")
        $headAfter = Invoke-Git -GitArgs @("rev-parse", "HEAD") -Repo $fixture.Work
        $status = Invoke-Git -GitArgs @("status", "--porcelain") -Repo $fixture.Work
        $mergeHeadExists = Test-Path -LiteralPath (Join-Path $fixture.Work ".git\MERGE_HEAD")
        Pop-Location

        Assert-Contains $output "git merge --no-commit --no-ff upstream/main" "sync-dev no-commit merge"
        Assert-Contains $output "Merge is staged but not committed" "sync-dev no-commit merge"
        Assert-Contains $status "README.md" "sync-dev no-commit merge"
        Assert-Contains $headAfter $headBefore.Trim() "sync-dev no-commit merge"
        Assert-True $mergeHeadExists "sync-dev no-commit merge"
    } finally {
        if ((Get-Location).Path -eq $fixture.Work) { Pop-Location }
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force
    }
}

function Test-SyncDevDoesNotUseRejectPatchFlow {
    $scriptPath = Join-Path $ScriptRoot "sync-dev.ps1"
    $script = Get-Content -LiteralPath $scriptPath -Raw

    Assert-NotContains $script "git apply --reject" "sync-dev reject patch flow"
    Assert-NotContains $script "*.rej" "sync-dev reject patch flow"
    Assert-NotContains $script ".rej" "sync-dev reject patch flow"
}

function Test-RejectPatchFilesAreIgnored {
    $repoRoot = Split-Path -Parent $ScriptRoot
    Assert-FileContains (Join-Path $repoRoot ".gitignore") "*.rej" "reject patch gitignore"
}

function Test-SyncUpstreamScriptIsRemoved {
    $scriptPath = Join-Path $ScriptRoot "sync-upstream.ps1"
    if (Test-Path -LiteralPath $scriptPath) {
        throw "sync-upstream removal failed: sync-upstream.ps1 should not exist"
    }
}

Test-SyncDevExitsWhenUserDeclinesDevCheckout
Test-SyncDevRunsNoCommitMergeForManualReview
Test-SyncDevDoesNotUseRejectPatchFlow
Test-RejectPatchFilesAreIgnored
Test-SyncUpstreamScriptIsRemoved

Write-Host "sync script tests passed"
