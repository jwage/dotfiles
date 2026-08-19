# Dotfiles

Custom Omarchy/Hyprland/shell config is tracked in the private repo
`~/Repositories/dotfiles` (github.com/jwage/dotfiles) and symlinked into
place via its `install.sh` — see that repo's README for what's tracked and
why.

**Whenever you edit a config file, check whether it's a symlink into that
repo** (`readlink -f <path>` starts with `/home/jwage/Repositories/dotfiles`).
If it is, commit (and push) the change there once you've confirmed the
change works — don't leave the dotfiles repo behind live config edits.

**If you create a new Omarchy/Hyprland customization that isn't tracked yet**
(a new plugin, a new hypr config file, etc.), bring it into the dotfiles repo
the same way the existing files are: copy it in, symlink the live path back
to the repo copy, add an entry to `install.sh`, commit, and push — rather
than leaving it as an untracked file that a fresh install/distro-switch would
lose.

Never commit secrets/keys into that repo (see its README for what's already
excluded and why).
