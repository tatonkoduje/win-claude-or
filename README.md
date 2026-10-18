# win-claude-or

Run Claude Code on Windows with models available through [OpenRouter](https://openrouter.ai).

This project is a Windows-oriented port of [`claude-or`](https://github.com/dariusz-przada/claude-or).
The goal is to keep the convenient alias workflow while supporting a native Claude Code
installation, PowerShell and Git Bash.

> **Status:** Early Windows port. The PowerShell launcher, `.cmd` wrapper, JSON aliases and
> OpenRouter key manager are included; more compatibility testing is still needed.

## Why this project exists

Claude Code normally uses the Anthropic or claude.ai authentication configured on your machine.
`win-claude-or` is intended to let you start one Claude Code process with an OpenRouter model,
without changing your normal Claude Code setup.

The workflow looks like this:

```powershell
win-claude-or ccds -p "Explain this repository"
win-claude-or ccqwen --resume
win-claude-or --list
```

Each alias maps a short command to an OpenRouter model. The environment variables are scoped to
that one Claude Code process, so running plain `claude` continues to use your normal login.

## Requirements

- Windows 10 or Windows 11
- PowerShell 7 recommended, or Git Bash
- [Claude Code](https://claude.ai/code) installed and available as `claude`
- An [OpenRouter](https://openrouter.ai) account and API key
- Git
- `jq` for Git Bash workflows and JSON configuration

Verify the current Claude Code installation:

```powershell
claude --version
```

If `claude` is not recognized after installation, add this directory to your user `PATH`:

```text
C:\Users\<your-user>\.local\bin
```

For the default installation on this machine:

```text
C:\Users\aru\.local\bin
```

## Planned default aliases

| Command | OpenRouter model |
|---|---|
| `ccds` | `deepseek/deepseek-v4-pro` |
| `ccdsf` | `deepseek/deepseek-v4-flash` |
| `cckimi` | `moonshotai/kimi-k3` |
| `ccglm` | `z-ai/glm-5.3` |
| `ccqwen` | `qwen/qwen3-coder-next` |
| `ccfree` | `openrouter/free` |

Model names and availability can change. Check the current catalogue at
[openrouter.ai/models](https://openrouter.ai/models) before adding an alias.

## Configuration location on Windows

The Windows version will keep its configuration in:

```text
C:\Users\<your-user>\.config\claude-or\
```

| File | Purpose |
|---|---|
| `aliases.json` | Alias-to-model definitions |
| `keys.json` | Saved OpenRouter keys and the active key |

API keys must never be committed to this repository. The configuration directory should be added
to `.gitignore` if it is created inside a project checkout.

## OpenRouter API key

For a temporary PowerShell session:

```powershell
$env:OPENROUTER_API_KEY = 'sk-or-v1-...'
```

For a one-off command, prefer reading the key without putting it in shell history. The final
Windows key manager will provide a hidden prompt and named keys, matching the original project.

Do not paste real API keys into README files, issues, commits or screenshots.

## Installation from source

Clone the repository:

```powershell
git clone https://github.com/dariusz-przada/win-claude-or.git
cd win-claude-or
```

Run the launcher from the checkout:

```powershell
.\win-claude-or.cmd --list
.\win-claude-or.cmd --sync
```

The launcher stores aliases and encrypted user-scoped keys under
`C:\Users\<your-user>\.config\claude-or\`. Add the alias directory below to your user `PATH` if
you want to run commands such as `ccds` directly:

```text
C:\Users\<your-user>\.local\bin
```

The `.cmd` wrapper works from PowerShell, Command Prompt and Git Bash. It uses PowerShell 7 when
available and falls back to Windows PowerShell.

## Design goals

- Native Windows support without requiring WSL.
- PowerShell commands first; Git Bash compatibility where practical.
- No changes to the user's normal `claude` authentication.
- Per-process OpenRouter environment variables.
- JSON-based aliases that can be listed, added, updated, linked and removed.
- Safe handling of API keys without storing secrets in the repository.
- Clear warnings when a model is unknown to Claude Code or has limited tool support.

## Relationship to the original project

The original project is the reference implementation for the alias and OpenRouter workflow:

<https://github.com/dariusz-przada/claude-or>

`win-claude-or` is intended to adapt that workflow to Windows rather than replace the original
project. See the original README for the complete command model and behavior that the Windows port
aims to preserve.

## Contributing

The first implementation steps are:

1. Improve compatibility with different Claude Code and PowerShell versions.
2. Add automated Windows tests for aliases, key storage and command shims.
3. Add a proper release/update channel for the Windows launcher.
4. Test with the native Claude Code executable on Windows.

## License

This project follows the license of the original implementation. See `LICENSE` once the Windows
port is ready for its first release.
