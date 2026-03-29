# Coding Agent Safety Net

A Copilot CLI plugin that guards dangerous operations with context-aware permission prompts.

When a Copilot CLI agent tries to run a destructive command — `git push`, `git reset --hard`,
`npm publish`, `Remove-Item -Recurse`, and [23 more patterns](#guarded-operations) — this hook
intercepts it, shows you exactly what's about to happen, and asks for your explicit approval.

## Installation

### Option 1: Copilot CLI Plugin (recommended)

1. Add the marketplace:
   ```
   /plugin marketplace add BerserkerDotNet/CodingAgentSafetyNet
   ```

2. Install the plugin:
   ```
   /plugin install safety-net@coding-agent-safety-net-marketplace
   ```

The hook is now active for all future sessions.

### Option 2: Manual Install

1. Copy `hooks.json` into your repo's `.github/hooks/` directory:
   ```powershell
   New-Item -ItemType Directory -Path ".github\hooks" -Force
   Copy-Item .github/plugins/safety-net/hooks.json ".github\hooks\"
   Copy-Item .github/plugins/safety-net/guard-dangerous-ops.ps1 ".github\hooks\"
   ```

2. Update the paths in `.github/hooks/hooks.json` to point to the script's new location:
   ```json
   {
     "version": 1,
     "hooks": {
       "preToolUse": [
         {
           "type": "command",
           "powershell": ".github/hooks/guard-dangerous-ops.ps1",
           "bash": "pwsh -NoProfile -File .github/hooks/guard-dangerous-ops.ps1",
           "cwd": ".",
           "timeoutSec": 10
         }
       ]
     }
   }
   ```

   Or, to install as a **user-level** hook (applies to all repos), copy to `~/.copilot/hooks/`
   and add the hook entry to `~/.copilot/config.json` under the `hooks` key.

### Verify Installation

Start a new Copilot CLI session and try a dangerous command (e.g. `git commit`).
You should see a "Hook permission request" with the operation details before the
standard tool approval prompt.

## How It Works

The hook runs as a `preToolUse` handler in Copilot CLI:

1. Fires on every `powershell` tool call (how Copilot runs shell commands on Windows)
2. Parses composite commands (`&&`, `||`, `;`) into individual segments
3. Pattern-matches each segment against the dangerous operations list
4. **Safe commands** → pass through silently (no output = allow)
5. **Dangerous commands** → returns `permissionDecision: "ask"` with a detailed reason

The Copilot CLI permission prompt then shows the context and lets you approve or reject.

```
⚠️  DANGEROUS OPERATION DETECTED

  • git push --force: REWRITES remote history — may lose others' commits
    Command: git push --force origin master
```

## Guarded Operations

| Category | Operations |
|----------|-----------|
| **Git State-Changing** | commit, push, push --force, push --delete, reset, reset --hard, checkout --, restore --worktree, clean, branch -D, stash drop/clear, rebase, merge, tag -d |
| **Publishing** | npm publish, vsce publish, docker push, dotnet nuget push |
| **Destructive Files** | Remove-Item -Recurse, rm -rf |
| **Infrastructure** | kubectl delete, terraform destroy, terraform apply |

## Composite Commands

Chained commands are parsed and each segment is checked independently:

```
cd I:\Projects && git push origin master && echo "done"
→ Blocked: segment 'git push origin master' is dangerous
```

## Customization

Edit the `$DangerousPatterns` array at the top of `guard-dangerous-ops.ps1` to add, remove,
or modify patterns. Each entry has:

- **Pattern** — regex matched against each command segment (case-insensitive)
- **Label** — human-readable name shown in the permission prompt
- **Risk** — description of the danger

## Disabling

| Method | How |
|--------|-----|
| Temporarily | Set `"disableAllHooks": true` in `~/.copilot/config.json` |
| Permanently | Remove the `preToolUse` entry from `hooks` in config.json |

## License

MIT
