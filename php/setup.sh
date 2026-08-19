#!/usr/bin/env bash
# Install host PHP 8.5 + Composer/phpunit extensions on Omarchy (Arch) or
# macOS (Homebrew). Idempotent. See php/README.md.
#
# Does not install PHP via mise. Does not edit the system php.ini for
# memory_limit (that lives in php/cli.ini). Does not uncomment Arch
# /etc/php/conf.d stubs (php/linux/extensions.ini enables them for CLI).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS="$(uname -s)"
PIE="${HOME}/.local/bin/pie"
PG_QUERY_SO="${HOME}/.local/lib/php/pg_query.so"
REQUIRED_MODULES=(apcu gd gmp pgsql redis igbinary pg_query sodium sockets sysvsem)

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# php -m without this repo's scan dir, so we see what the OS package
# already enabled (brew php.ini) vs what we still need to add.
system_php_modules() {
  env -u PHP_INI_SCAN_DIR php -m 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

php_has_system() {
  system_php_modules | grep -qx "$1"
}

elevate() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif [[ ! -t 0 ]] && command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
  else
    sudo "$@"
  fi
}

install_pie() {
  mkdir -p "${HOME}/.local/bin"
  if [[ ! -x "${PIE}" ]]; then
    log "Downloading PIE to ${PIE}"
    curl -fsSL -o "${PIE}" \
      https://github.com/php/pie/releases/latest/download/pie.phar
    chmod +x "${PIE}"
  fi
}

install_pg_query() {
  install_pie
  mkdir -p "${HOME}/.local/lib/php"
  if [[ -f "${PG_QUERY_SO}" ]] && env -u PHP_INI_SCAN_DIR php -m 2>/dev/null | grep -qi '^pg_query$'; then
    log "ok      pg_query already loaded by system php.ini"
  fi
  if [[ ! -f "${PG_QUERY_SO}" ]]; then
    log "Building flow-php/pg-query-ext via PIE (-j1)"
    # --skip-enable-extension: we enable via php/local, not system php.ini.
    # -j1: libpg_query protobuf headers race under parallel make.
    "${PIE}" install flow-php/pg-query-ext -n --force -j1 \
      --skip-enable-extension --no-system-dependencies-check \
      || true
    local built
    built="$(find "${HOME}/.config/pie" -name 'pg_query.so' -type f 2>/dev/null | head -n 1 || true)"
    if [[ -z "${built}" ]]; then
      die "PIE did not produce pg_query.so (install build deps and re-run)"
    fi
    cp "${built}" "${PG_QUERY_SO}"
    log "copied  ${PG_QUERY_SO}"
  else
    log "ok      ${PG_QUERY_SO}"
  fi

  mkdir -p "${REPO_DIR}/php/local"
  cat > "${REPO_DIR}/php/local/pg_query.ini" <<'INI'
; Written by php/setup.sh (gitignored). Same path on macOS and Linux.
extension=${HOME}/.local/lib/php/pg_query.so
INI
  log "wrote   ${REPO_DIR}/php/local/pg_query.ini"
}

scan_dir_for_verify() {
  local scan="${REPO_DIR}/php"
  if [[ "${OS}" == "Linux" ]]; then
    scan="${scan}:${REPO_DIR}/php/linux"
  fi
  if [[ -d "${REPO_DIR}/php/local" ]]; then
    scan="${scan}:${REPO_DIR}/php/local"
  fi
  printf '%s:' "${scan}"
}

verify() {
  local missing=0 mod
  export PHP_INI_SCAN_DIR
  PHP_INI_SCAN_DIR="$(scan_dir_for_verify)"
  log ""
  log "php     $(command -v php) $(php -r 'echo PHP_VERSION;')"
  log "ini     PHP_INI_SCAN_DIR=${PHP_INI_SCAN_DIR}"
  for mod in "${REQUIRED_MODULES[@]}"; do
    if php -m 2>/dev/null | grep -qi "^${mod}$"; then
      log "ok      ext-${mod}"
    else
      log "MISSING ext-${mod}"
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    die "one or more required extensions are missing (see php/README.md)"
  fi
  log "PHP setup ok"
}

setup_linux() {
  command -v pacman >/dev/null 2>&1 || die "pacman not found (Omarchy/Arch expected)"
  log "Installing Arch PHP packages"
  elevate pacman -S --needed --noconfirm \
    php php-gd php-pgsql php-sodium php-apcu php-igbinary php-redis \
    protobuf-c gcc make pkgconf autoconf automake libtool curl
  install_pg_query
}

pecl_install_if_missing() {
  local name="$1"
  if php_has_system "${name}"; then
    log "ok      ext-${name} (already in system php.ini)"
    return
  fi
  command -v pecl >/dev/null 2>&1 || die "pecl not found (brew php should ship it)"
  log "pecl    install ${name}"
  printf '\n' | pecl install -f "${name}"
}

setup_macos() {
  command -v brew >/dev/null 2>&1 || die "Homebrew not found"
  log "Installing Homebrew php"
  brew install php protobuf-c pkg-config autoconf automake libtool
  local php_ver
  php_ver="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
  if [[ "${php_ver}" != "8.5" ]]; then
    log "warn    php ${php_ver} on PATH; TradersPost wants ~8.5.0 (brew install php@8.5 and put it first on PATH)"
  fi
  # gd/gmp/pgsql/sodium/sockets are usually compiled into brew PHP.
  # Only PECL-install what the system ini does not already load.
  pecl_install_if_missing apcu
  pecl_install_if_missing igbinary
  if php_has_system redis; then
    log "ok      ext-redis (already in system php.ini)"
  else
    command -v pecl >/dev/null 2>&1 || die "pecl not found"
    log "pecl    install redis"
    # igbinary / lzf / zstd / msgpack prompts
    printf 'yes\nyes\nyes\nyes\n' | pecl install -f redis
  fi
  install_pg_query
}

case "${OS}" in
  Linux) setup_linux ;;
  Darwin) setup_macos ;;
  *) die "unsupported OS: ${OS}" ;;
esac

verify
