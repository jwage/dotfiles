# Host PHP (Omarchy + macOS)

Agent source of truth for installing PHP so `composer install` and host
`phpunit --testsuite=unit` work. Humans: short version is in the repo
README `### PHP` section.

`install.sh` only symlinks config. It does **not** install PHP.

```sh
~/Repositories/dotfiles/php/setup.sh
```

Idempotent. Safe to re-run. Needs network, and on Omarchy a GUI auth
prompt (`pkexec`) when the agent has no TTY.

## Rules

- Install PHP with the OS package manager (`pacman` / `brew`), **not mise**.
- Keep both machines on PHP **8.5.x** (`php --version`). This repo does
  not pin it.
- `php/cli.ini` is **shared**: `memory_limit = -1` only. Never put
  `extension=` there — Homebrew PHP already enables gd/pgsql/sodium/sockets
  and a second `extension=gd` fatals with "already loaded".
- Arch enables those modules from `php/linux/extensions.ini` (CLI only).
  Leave `/etc/php/php.ini` and `/etc/php/conf.d/*.ini` stubs commented.
- `pg_query` is not packaged. `setup.sh` builds it with PIE, copies
  `~/.local/lib/php/pg_query.so`, and writes gitignored
  `php/local/pg_query.ini` using `${HOME}` (no `/home/jwage/...` paths).
- Do not `composer --ignore-platform-req=ext-*` to paper over missing
  extensions. Do not edit system php.ini for `memory_limit`.

## How CLI ini is loaded

`shell/env.sh` sets `PHP_INI_SCAN_DIR` from a login/interactive shell
(`zshrc` / `bashrc` only):

| OS | Directories scanned (then distro `conf.d` because of the trailing `:`) |
|---|---|
| Linux | `php/` (shared `cli.ini`) + `php/linux/` (Arch `extension=`) + `php/local/` if present |
| macOS | `php/` + `php/local/` if present |

php-fpm / Apache (systemd / launchd) never see this variable.

**Agents and GUI-launched Cursor often skip zshrc.** If `php --ini` does
not list `dotfiles/php/cli.ini`, export the same scan dir before Composer:

```sh
# Linux
export PHP_INI_SCAN_DIR="$HOME/Repositories/dotfiles/php:$HOME/Repositories/dotfiles/php/linux:$HOME/Repositories/dotfiles/php/local:"
# macOS (omit php/linux)
export PHP_INI_SCAN_DIR="$HOME/Repositories/dotfiles/php:$HOME/Repositories/dotfiles/php/local:"
```

Or source `shell/env.sh` after setting `DOTFILES` to this repo.

## What gets installed

Required for TradersPost `composer.json` (and typical host phpunit):

`ext-apcu` `ext-gd` `ext-gmp` `ext-pgsql` `ext-redis` `ext-igbinary`
`ext-pg_query` `ext-sodium` `ext-sockets` `ext-sysvsem`

(plus whatever the OS PHP build already has: bcmath, curl, intl, mbstring,
pcntl, zip, …)

| | Omarchy (Arch) | macOS (Homebrew) |
|---|---|---|
| PHP | `pacman -S php` | `brew install php` |
| Split packages | `php-gd php-pgsql php-sodium php-apcu php-igbinary php-redis` | usually built-in; PECL for apcu / igbinary / redis if `php -m` lacks them |
| `pg_query` | PIE `flow-php/pg-query-ext -j1` | same |
| Enable extras | tracked `php/linux/extensions.ini` (incl. `sysvsem` for Symfony `SemaphoreStore`) | brew/pecl `conf.d`; do **not** add `extension=gd` if `php -m` already lists it. `sysvsem` is usually built into brew PHP |
| Privilege | `pkexec` when there is no TTY; else `sudo` | `brew` as the user; PECL may ask for write access to the Cellar |

PIE lives at `~/.local/bin/pie`. Build `pg_query` with **`-j1`** (libpg_query
protobuf headers race under parallel make). `--skip-enable-extension` so
we enable via `php/local`, not `/etc/php/php.ini`.

## Verify

```sh
php -v                          # 8.5.x
php --ini                       # cli.ini (and linux/local) in the scan list
php -m                          # apcu gd gmp pgsql redis igbinary pg_query sodium sockets sysvsem
composer install
php -d xdebug.mode=off vendor/bin/phpunit --testsuite=unit
```

`make unit-tests` in TradersPost still runs **inside Docker**. Host phpunit
is for iterating without the container.

## TradersPost: root-owned Docker trees

Docker leaves generated dirs owned by root. Host Composer/phpunit then
fail with permission denied (`vendor/composer/installed.php`,
`var/sql_explain_captured.jsonl`, `.phpunit.cache/test-results`). Fix
ownership; do not treat this as a missing extension:

```sh
pkexec chown -R "$USER:$USER" vendor vendor-bin var .phpunit.cache
```

(`sudo` is fine in a terminal.)

## Privilege (Omarchy agents)

Use `sudo` in a visible terminal. Use `pkexec` when the caller cannot
prompt on a TTY (Cursor agent). `php/setup.sh` already picks this.
