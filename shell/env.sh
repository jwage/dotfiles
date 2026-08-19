# Sourced from bash/bashrc (Linux) and zsh/zshrc (macOS).
# Keep this file free of OS-specific paths.

# MCP API keys for Cursor / Claude Code (host-only; not in any repo)
[[ -r "$HOME/.config/mcp-secrets.env" ]] && source "$HOME/.config/mcp-secrets.env"

export PATH="$HOME/.config/composer/vendor/bin:$PATH"

# Run project-local Composer/PHP tools (phpunit, phpcs, phpcbf, ...) by bare
# name from a repo root, e.g. `phpunit` instead of `vendor/bin/phpunit`.
# Deliberately NOT done by putting bin/vendor/bin on PATH: relative PATH
# entries let ANY directory you cd into shadow real commands (CWE-426 --
# an untrusted repo could ship its own ./bin/ls or ./vendor/bin/git). This
# hook only runs when the shell's normal PATH lookup already found nothing,
# so it can never intercept a command that exists for real elsewhere on PATH.
_run_local_bin() {
  local cmd=$1
  shift
  local dir
  for dir in vendor/bin bin; do
    if [[ -x "$dir/$cmd" ]]; then
      "./$dir/$cmd" "$@"
      return $?
    fi
  done
  echo "command not found: $cmd" >&2
  return 127
}
command_not_found_handler() { _run_local_bin "$@"; } # zsh
command_not_found_handle()  { _run_local_bin "$@"; } # bash
