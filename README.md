# Ubuntu post install script

This script is intended to create development environment for PHP/Python/NodeJS with Apache/Nginx or Docker. It also installs some useful terminal utilities & applications.

## To run this script execute:
1. `chmod +x post-install.sh`
2. `sudo ./post-install.sh`

Once, on a clean install: it is not written to run twice (the zsh plugin clones fail on the
second run). **If it stops part-way**, it tells you why on the last lines; fix that, then run
the remaining sections by hand from the failing line down rather than the whole script again.
What it changes that you will notice afterwards: snapd is removed and pinned out, Firefox comes
from the mozillateam PPA, ufw is enabled with **default deny incoming** (allow ssh first if you
need it), the login shell becomes zsh, and Ollama is installed as a service.

## For gnome tweaks do same:
1. `chmod +x gnome-tweak.sh`
2. `./gnome-tweak.sh`, as your normal user. **Not** with sudo: the script refuses to run as
   root, because gsettings under sudo would change root's settings, not yours.

if you need to backup current system you can use `backup-home.sh` script. Usage is in comments at the top of the script.
## Fixes applied (2026-09)

Found on the 26.04 desktop, where an earlier copy of the script had run:

- **ShellCheck never checked the script.** A comment line starting `#   shellcheck` (in the
  tool list) was parsed as a ShellCheck directive and stopped the analysis with SC1073. It is
  capitalised now; ShellCheck then reports no warnings, only style notes (unquoted variables,
  `read` without `-r`).
- **Apache answered `403 Forbidden`.** Home directories are `750`, so `www-data` could not
  enter `~/web`, and `~/web` was created by root. An ACL now gives www-data traverse-only access
  to the home directory (`setfacl -m u:www-data:--x`), which was enough for `200`, while it still
  cannot list the home directory. Not by adding www-data to the user's group: desktop users have
  umask `0002`, so Apache could then write their group-writable files.
- **Two swap files.** The installer's `/swap.img` (4 GB) stayed in fstab beside the new 8 GB
  `/swapfile`. The script now grows `/swap.img` to 8 GB instead, and skips btrfs.
- **lazydocker and OpenCode landed in `/root`**, and `pipx ensurepath` edited root's `.bashrc`:
  their installers use `$HOME`, and they ran as root. They run as the user now. The OpenCode
  comment ("installed as an isolated uv tool") was wrong.
- **TLP was never installed on a laptop.** The test was `/sys/module/battery/initstate`, which
  does not exist when the battery driver is built into the kernel, as it is on Ubuntu. It now
  looks for a `Battery` in `/sys/class/power_supply/` that is not `scope=Device`, which is what a
  wireless mouse or headset reports (tested against a fake sysfs tree: a desktop with such a
  mouse no longer gets TLP, a laptop still does). Thresholds go to `/etc/tlp.d/` rather than
  being appended to the package's `/etc/tlp.conf`, and the comment now matches the values (it said
  "stop at 80 %"; the value is 95). `acpi-call-dkms` is no longer installed: TLP 1.8's ThinkPad
  plugins never call `acpi_call` (read from the package), so it was only a DKMS module to rebuild
  for every kernel.
- **Writing through the dotfiles' symlinks.** With the `dotfiles/` repo installed first,
  `cat > ~/.tmux.conf` overwrote the repo's file, and `git config --global` wrote the identity
  into the repo's `.gitconfig`. It now leaves an existing `~/.tmux.conf` alone, writes git settings
  to `~/.gitconfig.local` when `~/.gitconfig` is a link (tested: the repo file's checksum did not
  change), and installs Git LFS with `--system`, into `/etc/gitconfig`.
- **A download failure stopped the whole script.** `install_deb_from_url` returned 1, which
  under `set -e` ended the run half-way (Tabby's version comes from the rate-limited GitHub API).
  It warns and continues now, like the other optional apps.
- **`apt update && apt install ...` could fail silently.** In an `&&` list a failing `apt update`
  does not stop a `set -e` script; it skips the install. `apt update` fails (exit 100) on an
  unsigned repository or a held lock, though not on an unreachable one, which is only a warning.
  One command per line now.
- **kubectl came from the v1.30 repository**, long out of support. It now uses the current stable
  minor from `dl.k8s.io/release/stable.txt` (v1.37 in 2026-09).
- **The apt lock.** `wait_for_apt` checks with `fuser` and then calls apt, which leaves a gap for
  unattended-upgrades to take the lock. `apt` itself waits 120 s by default but `apt-get` does not
  wait at all (`Could not get lock`, exit 100), and the Docker and Brave installers use apt-get. A
  drop-in sets `DPkg::Lock::Timeout "600"` for the run and is removed on exit. That does **not**
  cover the lists lock that `apt update` takes: with it held, both `apt update` and `apt-get
  update` still failed at once (`Unable to lock directory /var/lib/apt/lists/`). So `apt update`
  goes through `apt_update()`, which retries on that error only (tested: it got through after two
  retries, and returned at once for anything else).
- `backup-home.sh` failed with `USER: unbound variable` when `$USER` was unset; it falls back to
  `id -un`.

Checked and left alone: every URL answered for 26.04, including packages.sury.org (PHP 8.0 to 8.6
for `resolute`), Docker's `resolute` suite and the mozillateam PPA. Pinned versions that have
aged: the nvm installer (v0.40.1; v0.40.8 is current) and MongoDB Compass 1.49.7 (1.51.0).

## Repairing a machine an earlier copy ran on

Run in a terminal on the desktop, as yourself. Each part stands alone. All three were run on the
lab desktop, which had the same leftovers, and checked again after a reboot.

**Apache answers 403.** `~/web` belongs to root, and `www-data` cannot enter your home directory:

```bash
sudo chown -R "$USER:" ~/web
# traverse only: www-data can reach ~/web but not list your home directory
sudo setfacl -m u:www-data:--x ~
# a test file, because an empty ~/web gives 403 anyway (nothing to serve, no listing)
echo ok > ~/web/test.html
# prints ok
curl -s http://localhost/test.html
rm ~/web/test.html
# "Permission denied": the home directory stays private
sudo -u www-data ls ~
```

**Two swap files.** `swapon --show` lists the installer's 4 GB `/swap.img` and the script's 8 GB
`/swapfile`. Keep `/swapfile`, and take `/swap.img` out of fstab too, or it returns at the next
boot:

```bash
swapon --show
sudo swapoff /swap.img
sudo sed -i.bak '\|^/swap\.img[[:space:]]|d' /etc/fstab
sudo rm /swap.img
sudo systemctl daemon-reload
# only /swapfile, here and after a reboot; the old fstab is /etc/fstab.bak
swapon --show
grep swap /etc/fstab
```

**No TLP.** It removes `power-profiles-daemon`, so the power-mode menu in the top bar loses its
profiles. Do not add `acpi-call-dkms`: TLP 1.8 does not use it.

```bash
sudo apt install tlp tlp-rdw
sudo tee /etc/tlp.d/50-thinkpad-battery.conf >/dev/null <<'EOF'
# ThinkPad battery charge thresholds: start charging below 40 %, stop at 95 %
# (75 and 80 for a laptop that mostly lives on the charger)
START_CHARGE_THRESH_BAT0=40
STOP_CHARGE_THRESH_BAT0=95
EOF
sudo tlp start
# TLP read the file
sudo tlp-stat --config | grep CHARGE_THRESH
# the battery took it: 40 and 95
cat /sys/class/power_supply/BAT0/charge_control_start_threshold \
    /sys/class/power_supply/BAT0/charge_control_end_threshold
```