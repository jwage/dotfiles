# Sourced from bash/bashrc (Linux) and zsh/zshrc (macOS).
# Keep this file free of OS-specific paths.

# MCP API keys for Cursor / Claude Code (host-only; not in any repo)
[[ -r "$HOME/.config/mcp-secrets.env" ]] && source "$HOME/.config/mcp-secrets.env"

# Project-local Composer/PHP tools (phpunit, phpcs, phpcbf, ...) when cwd is a repo.
export PATH="bin:vendor/bin:$HOME/.config/composer/vendor/bin:$PATH"
