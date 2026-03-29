<#
.SYNOPSIS
    Test suite for guard-dangerous-ops.ps1 preToolUse hook.

.DESCRIPTION
    Runs the hook script with various inputs and verifies the output.
    Exit code 0 = all tests pass, 1 = at least one failure.
#>

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..' '.github' 'plugins' 'safety-net' 'guard-dangerous-ops.ps1'
$scriptPath = (Resolve-Path $scriptPath).Path

$passed = 0
$failed = 0
$total  = 0

# ── Helpers ──────────────────────────────────────────────────────────────────

function Invoke-Hook {
    param(
        [string]$ToolName,
        [string]$Command,
        [string]$Description = 'test'
    )

    $argsJson = @{ command = $Command; description = $Description } | ConvertTo-Json -Compress
    $inputJson = @{
        timestamp = 1704614600000
        cwd       = 'C:/test'
        toolName  = $ToolName
        toolArgs  = $argsJson
    } | ConvertTo-Json -Compress

    $result = $inputJson | pwsh -NoProfile -NoLogo -File $scriptPath 2>&1
    return ($result | Out-String).Trim()
}

function Assert-ShouldAsk {
    param(
        [string]$TestName,
        [string]$Output,
        [string]$ExpectedLabel
    )
    $script:total++

    if (-not $Output) {
        $script:failed++
        Write-Host "  FAIL: $TestName — expected 'ask' but got no output" -ForegroundColor Red
        return
    }

    try {
        $json = $Output | ConvertFrom-Json
    } catch {
        $script:failed++
        Write-Host "  FAIL: $TestName — invalid JSON: $Output" -ForegroundColor Red
        return
    }

    if ($json.permissionDecision -ne 'ask') {
        $script:failed++
        Write-Host "  FAIL: $TestName — expected decision 'ask', got '$($json.permissionDecision)'" -ForegroundColor Red
        return
    }

    if ($ExpectedLabel -and $json.permissionDecisionReason -notmatch [regex]::Escape($ExpectedLabel)) {
        $script:failed++
        Write-Host "  FAIL: $TestName — expected label '$ExpectedLabel' in reason" -ForegroundColor Red
        Write-Host "         Reason: $($json.permissionDecisionReason)" -ForegroundColor DarkGray
        return
    }

    $script:passed++
    Write-Host "  PASS: $TestName" -ForegroundColor Green
}

function Assert-ShouldAllow {
    param(
        [string]$TestName,
        [string]$Output
    )
    $script:total++

    if ([string]::IsNullOrWhiteSpace($Output)) {
        $script:passed++
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        return
    }

    $script:failed++
    Write-Host "  FAIL: $TestName — expected no output (allow), got: $Output" -ForegroundColor Red
}

# ── Test Suite ───────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== Guard Dangerous Ops — Test Suite ===" -ForegroundColor Cyan
Write-Host ""

# ── Git: State-Changing ──────────────────────────────────────────────────────
Write-Host "Git State-Changing Operations:" -ForegroundColor Yellow

$out = Invoke-Hook -ToolName 'powershell' -Command 'git commit -m "initial"'
Assert-ShouldAsk 'git commit' $out 'git commit'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git push origin master'
Assert-ShouldAsk 'git push' $out 'git push'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git push --force origin master'
Assert-ShouldAsk 'git push --force' $out 'git push --force'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git push -f origin master'
Assert-ShouldAsk 'git push -f (short flag)' $out 'git push --force'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git push --delete origin feature'
Assert-ShouldAsk 'git push --delete' $out 'git push --delete'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git reset --hard HEAD~3'
Assert-ShouldAsk 'git reset --hard' $out 'git reset --hard'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git reset HEAD~1'
Assert-ShouldAsk 'git reset (soft)' $out 'git reset'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git checkout -- src/app.js'
Assert-ShouldAsk 'git checkout -- <path>' $out 'git checkout -- <path>'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git restore --worktree src/app.js'
Assert-ShouldAsk 'git restore --worktree' $out 'git restore --worktree'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git clean -fd'
Assert-ShouldAsk 'git clean' $out 'git clean'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git branch -D feature-old'
Assert-ShouldAsk 'git branch -D' $out 'git branch -D'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git stash drop stash@{0}'
Assert-ShouldAsk 'git stash drop' $out 'git stash drop/clear'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git stash clear'
Assert-ShouldAsk 'git stash clear' $out 'git stash drop/clear'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git rebase -i HEAD~5'
Assert-ShouldAsk 'git rebase' $out 'git rebase'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git merge feature-branch'
Assert-ShouldAsk 'git merge' $out 'git merge'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git tag -d v1.0.0'
Assert-ShouldAsk 'git tag -d' $out 'git tag -d'

# ── Publishing ───────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Publishing Operations:" -ForegroundColor Yellow

$out = Invoke-Hook -ToolName 'powershell' -Command 'npm publish'
Assert-ShouldAsk 'npm publish' $out 'npm publish'

$out = Invoke-Hook -ToolName 'powershell' -Command 'npx @vscode/vsce publish -p token'
Assert-ShouldAsk 'vsce publish' $out 'vsce publish'

$out = Invoke-Hook -ToolName 'powershell' -Command 'docker push myimage:latest'
Assert-ShouldAsk 'docker push' $out 'docker push'

$out = Invoke-Hook -ToolName 'powershell' -Command 'dotnet nuget push pkg.nupkg --source nuget.org'
Assert-ShouldAsk 'dotnet nuget push' $out 'dotnet nuget push'

# ── Destructive File Ops ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "Destructive File Operations:" -ForegroundColor Yellow

$out = Invoke-Hook -ToolName 'powershell' -Command 'Remove-Item -Path .\dist -Recurse -Force'
Assert-ShouldAsk 'Remove-Item -Recurse' $out 'Remove-Item -Recurse'

$out = Invoke-Hook -ToolName 'powershell' -Command 'rm -rf ./node_modules'
Assert-ShouldAsk 'rm -rf' $out 'rm -rf'

# ── Infrastructure ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Infrastructure Operations:" -ForegroundColor Yellow

$out = Invoke-Hook -ToolName 'powershell' -Command 'kubectl delete pod my-pod'
Assert-ShouldAsk 'kubectl delete' $out 'kubectl delete'

$out = Invoke-Hook -ToolName 'powershell' -Command 'terraform destroy -auto-approve'
Assert-ShouldAsk 'terraform destroy' $out 'terraform destroy'

$out = Invoke-Hook -ToolName 'powershell' -Command 'terraform apply -auto-approve'
Assert-ShouldAsk 'terraform apply' $out 'terraform apply'

# ── Composite Commands ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "Composite Commands:" -ForegroundColor Yellow

$out = Invoke-Hook -ToolName 'powershell' -Command 'cd I:\Projects && git push origin master && echo done'
Assert-ShouldAsk 'composite: cd && git push && echo' $out 'git push'

$out = Invoke-Hook -ToolName 'powershell' -Command 'git add -A && git commit -m "fix" && git push origin master'
Assert-ShouldAsk 'composite: add && commit && push' $out 'git commit'

$out = Invoke-Hook -ToolName 'powershell' -Command 'npm test || git reset --hard HEAD'
Assert-ShouldAsk 'composite: test || reset (pipe-or)' $out 'git reset --hard'

$out = Invoke-Hook -ToolName 'powershell' -Command 'echo start; git clean -fd; echo end'
Assert-ShouldAsk 'composite: semicolon separated' $out 'git clean'

# ── Safe Commands (should pass through) ──────────────────────────────────────
Write-Host ""
Write-Host "Safe Commands (should allow):" -ForegroundColor Yellow

$out = Invoke-Hook -ToolName 'powershell' -Command 'git --no-pager status'
Assert-ShouldAllow 'git status' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'git --no-pager log --oneline -10'
Assert-ShouldAllow 'git log' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'git --no-pager diff'
Assert-ShouldAllow 'git diff' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'git --no-pager branch -a'
Assert-ShouldAllow 'git branch -a (list, not delete)' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'git add -A'
Assert-ShouldAllow 'git add' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'git stash'
Assert-ShouldAllow 'git stash (save)' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'git stash list'
Assert-ShouldAllow 'git stash list' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'npm test'
Assert-ShouldAllow 'npm test' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'npm run build && npm run lint'
Assert-ShouldAllow 'npm build && lint' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'Get-ChildItem -Path .\src'
Assert-ShouldAllow 'Get-ChildItem (no -Recurse danger)' $out

# ── Non-powershell Tools (should pass through) ──────────────────────────────
Write-Host ""
Write-Host "Non-powershell Tools (should allow):" -ForegroundColor Yellow

$out = Invoke-Hook -ToolName 'edit' -Command 'git push origin master'
Assert-ShouldAllow 'edit tool (ignored)' $out

$out = Invoke-Hook -ToolName 'view' -Command 'git reset --hard'
Assert-ShouldAllow 'view tool (ignored)' $out

$out = Invoke-Hook -ToolName 'create' -Command 'rm -rf /'
Assert-ShouldAllow 'create tool (ignored)' $out

# ── Composite: all safe segments ─────────────────────────────────────────────
Write-Host ""
Write-Host "Composite Safe Commands:" -ForegroundColor Yellow

$out = Invoke-Hook -ToolName 'powershell' -Command 'git --no-pager status && git --no-pager diff && npm test'
Assert-ShouldAllow 'composite: status && diff && test' $out

$out = Invoke-Hook -ToolName 'powershell' -Command 'cd src && Get-ChildItem; echo done'
Assert-ShouldAllow 'composite: cd && ls; echo' $out

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Results: $passed passed, $failed failed, $total total" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

if ($failed -gt 0) {
    exit 1
}
exit 0
