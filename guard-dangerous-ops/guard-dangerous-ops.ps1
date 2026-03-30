<#
.SYNOPSIS
    Copilot CLI preToolUse hook — guards dangerous operations by returning "ask" permission.

.DESCRIPTION
    Intercepts powershell tool calls, splits composite commands, and pattern-matches
    each segment against a configurable list of dangerous operations. When a match is
    found, returns {"permissionDecision":"ask","permissionDecisionReason":"..."} so the
    user sees context and decides via Copilot's built-in permission prompt.

    Install: register in ~/.copilot/config.json under hooks.preToolUse
#>

$ErrorActionPreference = 'Stop'

# ── Dangerous operation patterns ────────────────────────────────────────────
# Each entry: [regex pattern, human-readable label, risk description]
# Patterns are matched case-insensitively against individual command segments.

$DangerousPatterns = @(
    # ── Git: State-Changing ──────────────────────────────────────────────────
    @{ Pattern = '(?<!\-\-)(?<!\w)git\s+commit\b';             Label = 'git commit';              Risk = 'Creates permanent commit history' }
    @{ Pattern = '(?<!\w)git\s+push\b.*(\s+--force\b|\s+-f\b)'; Label = 'git push --force';       Risk = 'REWRITES remote history — may lose others'' commits' }
    @{ Pattern = '(?<!\w)git\s+push\b.*\s+--delete\b';          Label = 'git push --delete';      Risk = 'Deletes remote branch or tag' }
    @{ Pattern = '(?<!\w)git\s+push\b';                          Label = 'git push';               Risk = 'Publishes commits to remote' }
    @{ Pattern = '(?<!\w)git\s+reset\s+--hard\b';               Label = 'git reset --hard';        Risk = 'DISCARDS all uncommitted changes' }
    @{ Pattern = '(?<!\w)git\s+reset\b';                         Label = 'git reset';              Risk = 'Moves HEAD — may lose commits' }
    @{ Pattern = '(?<!\w)git\s+checkout\s+--\s';                 Label = 'git checkout -- <path>';  Risk = 'Discards uncommitted file changes' }
    @{ Pattern = '(?<!\w)git\s+restore\b.*--worktree\b';        Label = 'git restore --worktree';  Risk = 'Discards working tree changes' }
    @{ Pattern = '(?<!\w)git\s+clean\b';                         Label = 'git clean';              Risk = 'Deletes untracked files permanently' }
    @{ Pattern = '(?<!\w)git\s+branch\s+-(D|.*--delete\s+--force)\b'; Label = 'git branch -D';    Risk = 'Force-deletes branch (even if unmerged)' }
    @{ Pattern = '(?<!\w)git\s+stash\s+(drop|clear)\b';         Label = 'git stash drop/clear';    Risk = 'Permanently removes stash entries' }
    @{ Pattern = '(?<!\w)git\s+rebase\b';                        Label = 'git rebase';             Risk = 'Rewrites commit history' }
    @{ Pattern = '(?<!\w)git\s+merge\b';                         Label = 'git merge';              Risk = 'Combines branches — may create merge commits' }
    @{ Pattern = '(?<!\w)git\s+tag\s+-d\b';                      Label = 'git tag -d';             Risk = 'Deletes a tag' }

    # ── Publishing / Deployment ──────────────────────────────────────────────
    @{ Pattern = '(?<!\w)npm\s+publish\b';                       Label = 'npm publish';            Risk = 'Publishes package to npm registry' }
    @{ Pattern = 'vsce\s+publish\b';                             Label = 'vsce publish';           Risk = 'Publishes extension to VS Code Marketplace' }
    @{ Pattern = '(?<!\w)docker\s+push\b';                       Label = 'docker push';            Risk = 'Publishes container image to registry' }
    @{ Pattern = '(?<!\w)dotnet\s+nuget\s+push\b';              Label = 'dotnet nuget push';      Risk = 'Publishes NuGet package' }

    # ── Destructive File Operations ──────────────────────────────────────────
    @{ Pattern = 'Remove-Item\b.*-Recurse\b';                   Label = 'Remove-Item -Recurse';   Risk = 'Recursively deletes files/directories' }
    @{ Pattern = '(?<!\w)rm\s+-rf\b';                            Label = 'rm -rf';                Risk = 'Recursively force-deletes files' }

    # ── Infrastructure ───────────────────────────────────────────────────────
    @{ Pattern = '(?<!\w)kubectl\s+delete\b';                    Label = 'kubectl delete';         Risk = 'Deletes Kubernetes resources' }
    @{ Pattern = '(?<!\w)terraform\s+destroy\b';                 Label = 'terraform destroy';      Risk = 'Tears down infrastructure' }
    @{ Pattern = '(?<!\w)terraform\s+apply\b';                   Label = 'terraform apply';        Risk = 'Modifies infrastructure' }
)

# ── Helper: split composite commands ────────────────────────────────────────
# Splits on &&, ||, ; while respecting single/double quotes.
function Split-CompositeCommand {
    param([string]$Command)

    $segments = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inSingle = $false
    $inDouble = $false
    $i = 0

    while ($i -lt $Command.Length) {
        $ch = $Command[$i]

        # Track quote state
        if ($ch -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle }
        elseif ($ch -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble }

        if (-not $inSingle -and -not $inDouble) {
            # Check for && or ||
            if ($i + 1 -lt $Command.Length) {
                $two = $Command.Substring($i, 2)
                if ($two -eq '&&' -or $two -eq '||') {
                    $seg = $current.ToString().Trim()
                    if ($seg) { $segments.Add($seg) }
                    $current.Clear() | Out-Null
                    $i += 2
                    continue
                }
            }
            # Check for ;
            if ($ch -eq ';') {
                $seg = $current.ToString().Trim()
                if ($seg) { $segments.Add($seg) }
                $current.Clear() | Out-Null
                $i++
                continue
            }
        }

        $current.Append($ch) | Out-Null
        $i++
    }

    $seg = $current.ToString().Trim()
    if ($seg) { $segments.Add($seg) }

    return $segments
}

# ── Helper: match a command segment against dangerous patterns ──────────────
function Test-DangerousSegment {
    param([string]$Segment)

    foreach ($entry in $DangerousPatterns) {
        if ($Segment -match $entry.Pattern) {
            return $entry
        }
    }
    return $null
}

# ── Main ────────────────────────────────────────────────────────────────────

# Read JSON input from stdin
$jsonInput = [Console]::In.ReadToEnd()
$hookInput = $jsonInput | ConvertFrom-Json

# Only inspect powershell tool calls
if ($hookInput.toolName -ne 'powershell') {
    exit 0
}

# Parse tool args to extract the command
$toolArgs = $hookInput.toolArgs | ConvertFrom-Json
$command = $toolArgs.command
if (-not $command) {
    exit 0
}

# Split composite commands and check each segment
$segments = Split-CompositeCommand -Command $command
$matches = [System.Collections.Generic.List[hashtable]]::new()

foreach ($seg in $segments) {
    $match = Test-DangerousSegment -Segment $seg
    if ($match) {
        $matches.Add(@{
            Segment = $seg
            Label   = $match.Label
            Risk    = $match.Risk
        })
    }
}

# No dangerous segments found — allow silently
if ($matches.Count -eq 0) {
    exit 0
}

# Build the permission reason with context
$reasons = [System.Text.StringBuilder]::new()
$reasons.AppendLine("⚠️  DANGEROUS OPERATION DETECTED") | Out-Null

foreach ($m in $matches) {
    $reasons.AppendLine("  • $($m.Label): $($m.Risk)") | Out-Null
    $reasons.AppendLine("    Command: $($m.Segment)") | Out-Null
}

if ($matches.Count -gt 1 -or $segments.Count -gt 1) {
    $reasons.AppendLine("Full composite command: $command") | Out-Null
}

# Return "ask" so Copilot's permission prompt shows the context
$output = @{
    permissionDecision       = 'ask'
    permissionDecisionReason = $reasons.ToString().TrimEnd()
} | ConvertTo-Json -Compress

Write-Output $output
exit 0
