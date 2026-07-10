#!/bin/bash
# Post install script for Ubuntu 26.04 (GNOME) - Web Dev Setup
# Run only on clean install!
# Ref (reviewed for ideas): https://github.com/franckferman/ubuntu-post-install

set -e

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run with root privileges"
  exit 1
fi

# Avoid interactive prompts during package installs (EULAs, service restarts, etc.)
export DEBIAN_FRONTEND=noninteractive

# ─── Helpers ──────────────────────────────────────────────────────────────────
# Fresh Ubuntu runs apt-daily/unattended-upgrades on first boot, which holds the
# dpkg lock. Wait for it to finish so our first apt call doesn't fail with
# "Could not get lock /var/lib/dpkg/lock-frontend".
wait_for_apt() {
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock >/dev/null 2>&1; do
    [[ $waited -eq 0 ]] && echo "Waiting for another package manager (apt-daily/unattended-upgrades) to finish..."
    sleep 5
    waited=$((waited + 5))
    if [[ $waited -ge 600 ]]; then
      echo "apt still locked after 10 minutes — aborting."
      exit 1
    fi
  done
}

# Abort early if there's no network — this script pulls from ~15 external sources.
check_internet() {
  echo "Checking internet connectivity..."
  if ! ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 && ! ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
    echo "No internet connectivity detected — this script needs network access. Aborting."
    exit 1
  fi
}

# Download a .deb to a temp file, install it (gdebi auto-fixes deps), clean up.
# Args: <url> [display_name]
install_deb_from_url() {
  local url="$1" name="${2:-package}" tmp
  tmp="$(mktemp --suffix=.deb)"
  echo "Downloading ${name}..."
  if ! wget -qO "$tmp" "$url"; then
    echo "Failed to download ${name} from ${url}"
    rm -f "$tmp"
    return 1
  fi
  gdebi -n "$tmp"
  rm -f "$tmp"
}

echo "System user name?"
read -e system_user_name

echo "GIT user.name?"
read -e git_config_user_name

echo "GIT user.email?"
read -e git_config_user_email

echo "MySQL 'admin' user password? (local dev DB user)"
read -s mysql_admin_pass
echo

# Validate the account exists before building paths / running sudo -u against it
if [[ -z "$system_user_name" ]] || ! id "$system_user_name" >/dev/null 2>&1; then
  echo "User '$system_user_name' does not exist — aborting."
  exit 1
fi

USER_HOME="/home/${system_user_name}"
XDEBUG_DIR="${USER_HOME}/xdebug"

# Create + enter a writable CWD (~/Downloads may not exist yet on a TTY-first run)
mkdir -p "${USER_HOME}/Downloads" && cd "${USER_HOME}/Downloads"

# ─── Update ───────────────────────────────────────────────────────────────────
check_internet
wait_for_apt
echo "Updating system"
apt update && apt dist-upgrade -y && apt autoremove -y && apt autoclean -y

# ─── CPU Microcode ────────────────────────────────────────────────────────────
echo "Installing CPU microcode"
vendor=$(lscpu | awk '/Vendor ID/{print $3}')
if [[ "$vendor" == "GenuineIntel" ]]; then
  apt install -y intel-microcode
elif [[ "$vendor" == "AuthenticAMD" ]]; then
  apt install -y amd64-microcode
else
  echo "CPU vendor: $vendor — check microcode manually"
fi

# ─── Restricted Extras ────────────────────────────────────────────────────────
echo "Installing restricted extras (codecs, fonts)"
apt install -y ubuntu-restricted-extras

# ─── Essential Packages & CLI Utils ──────────────────────────────────────────
echo "Installing essentials & CLI utils"
# NOTE: comments must NOT sit on '\'-continued lines — bash treats the backslash
# as escaping a space, the '#' starts a comment, and the command ends early.
# Modern CLI tool reference (see aliases/symlinks set up later):
#   tmux           terminal multiplexer — persistent sessions, splits, detach over SSH
#   fastfetch      system info display (neofetch is archived upstream)
#   xclip          clipboard from CLI — `cat file | xclip -selection clipboard`
#   htop           interactive process viewer
#   ncdu           ncurses disk usage — see what's eating space
#   glances        rich system monitor (CPU/RAM/net/disk)
#   bat            cat + syntax highlighting (binary: batcat → symlinked to `bat`)
#   eza            modern ls with icons, git status, tree view
#   fzf            fuzzy finder — Ctrl+R becomes interactive history search
#   zoxide         smarter cd — `z proj` jumps to frequent dirs
#   ripgrep        fast grep, respects .gitignore — `rg "pattern"`
#   fd-find        fast find replacement (binary: fdfind → symlinked to `fd`)
#   jq             command-line JSON processor
#   direnv         per-directory environment variables
#   meld           visual diff/merge tool
#   shellcheck     shell-script linter (catches bugs like the '\'+comment one)
#   shfmt          shell-script formatter
#   flameshot      annotated screenshots
#   copyq          clipboard history manager
#   wavemon        wireless signal monitor (ncurses)
#   speedtest-cli  bandwidth test from terminal
apt install -y \
  software-properties-common apt-transport-https ca-certificates lsb-release gnupg \
  wget curl net-tools \
  network-manager-openvpn network-manager-openconnect-gnome \
  synaptic gnome-shell-extensions gnome-tweaks gnome-shell-extension-manager \
  gdebi gdebi-core trash-cli gparted stow \
  keepassxc bleachbit awscli \
  terminator tmux fastfetch xclip htop ncdu glances \
  bat eza fzf zoxide ripgrep fd-find jq direnv meld \
  shellcheck shfmt flameshot copyq \
  wavemon speedtest-cli

# bat & fd install under alternate binary names on Debian/Ubuntu (batcat, fdfind)
# because of naming conflicts — symlink them to the conventional names so the
# `cat`/`fd` aliases (and muscle memory) work. ~/.local/bin is added to PATH in .zshrc.
echo "Linking bat/fd to conventional names"
sudo -u $system_user_name mkdir -p ${USER_HOME}/.local/bin
sudo -u $system_user_name ln -sf "$(command -v batcat)" ${USER_HOME}/.local/bin/bat
sudo -u $system_user_name ln -sf "$(command -v fdfind)" ${USER_HOME}/.local/bin/fd

# ─── Python + uv ─────────────────────────────────────────────────────────────
echo "Installing Python + uv"
apt install -y python3-pip python3-venv python3-dev build-essential libssl-dev libffi-dev
# uv: fast Python package/project manager — replaces pip+venv, much faster installs
sudo -u $system_user_name bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'

# ─── Pipx ─────────────────────────────────────────────────────────────
echo "Installing pipx"
apt install -y pipx
pipx ensurepath

# ─── Java (OpenJDK — default-jdk = compiler + tools, not just runtime) ────────
echo "Installing Java (default-jdk)"
apt install -y default-jdk
java -version

# ─── OpenSSH Client ───────────────────────────────────────────────────────────
echo "Installing OpenSSH client"
apt install -y openssh-client

# ─── Tabby — SSH/Terminal Manager (replaces EOL Snowflake) ───────────────────
# Cross-platform SSH manager + terminal: tabs, splits, SFTP browser, key management
echo "Installing Tabby"
TABBY_TAG=$(curl -s https://api.github.com/repos/Eugeny/tabby/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
TABBY_VER="${TABBY_TAG#v}"
install_deb_from_url "https://github.com/Eugeny/tabby/releases/latest/download/tabby-${TABBY_VER}-linux-x64.deb" "Tabby"

# ─── Firewall ─────────────────────────────────────────────────────────────────
echo "Configuring firewall (ufw)"
apt install -y gufw
ufw enable
ufw default deny incoming
ufw default allow outgoing

# ─── Extractors ───────────────────────────────────────────────────────────────
echo "Installing archive extractors"
apt install -y unace rar unrar zip unzip p7zip-full \
  sharutils uudeview mpack arj cabextract file-roller
# 26.04 migrated to upstream 7-Zip: the RAR plugin p7zip-rar was renamed 7zip-rar
# (multiverse) and may lag — install best-effort so it can't abort the run.
apt install -y 7zip-rar || echo "  ! 7zip-rar unavailable — skipping (unrar still handles RAR)"

# ─── Fonts (Nerd Font for icons in eza/tmux/zsh + coding ligatures) ──────────
echo "Installing fonts (FiraCode + FiraCode Nerd Font)"
apt install -y fonts-firacode
sudo -u $system_user_name mkdir -p ${USER_HOME}/.local/share/fonts
if wget -qO /tmp/FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip; then
  sudo -u $system_user_name unzip -oq /tmp/FiraCode.zip -d ${USER_HOME}/.local/share/fonts/FiraCodeNerdFont
  rm -f /tmp/FiraCode.zip
  sudo -u $system_user_name fc-cache -f
else
  echo "  ! Could not download FiraCode Nerd Font — skipping (icons may render as boxes)"
fi

# ─── Android Tools ────────────────────────────────────────────────────────────
echo "Installing Android platform tools (adb, fastboot)"
apt install -y android-tools-adb android-tools-fastboot

# ─── Git ──────────────────────────────────────────────────────────────────────
echo "Installing & configuring Git"
apt install -y git git-lfs
sudo -u $system_user_name git config --global user.name "$git_config_user_name"
sudo -u $system_user_name git config --global user.email "$git_config_user_email"
sudo -u $system_user_name git lfs install   # enable large-file support globally
sudo -u $system_user_name git config --global init.defaultBranch master

# ─── Dev Network & Debug Tools ────────────────────────────────────────────────
#   dnsutils            dig/nslookup — DNS debugging
#   whois/traceroute/mtr-tiny/nmap — network path & port debugging
#   postgresql-client   psql CLI (the PHP pgsql driver is installed further down)
#   mkcert              locally-trusted HTTPS certs for *.test dev domains
echo "Installing dev network & debug tools"
apt install -y dnsutils whois traceroute mtr-tiny nmap postgresql-client
# mkcert best-effort (universe) — create + trust the local CA for the user
if apt install -y mkcert libnss3-tools; then
  sudo -u $system_user_name -H mkcert -install 2>/dev/null \
    || echo "  ! mkcert -install failed — run it once as your user after reboot"
else
  echo "  ! mkcert unavailable — install later: apt install mkcert && mkcert -install"
fi

# ─── Timeshift — system snapshots ────────────────────────────────────────────
# OS-level restore points (rsync/btrfs). Complements backup-home.sh (which only
# covers /home). Configure schedule via the Timeshift GUI after reboot.
echo "Installing Timeshift"
apt install -y timeshift

# ─── GitHub CLI ───────────────────────────────────────────────────────────────
echo "Installing GitHub CLI (gh)"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | gpg --batch --yes --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list
apt update && apt install -y gh

# ─── Subversion ───────────────────────────────────────────────────────────────
echo "Installing Subversion"
apt install -y subversion

# ─── Docker + Compose Plugin ──────────────────────────────────────────────────
echo "Installing Docker"
curl -fsSL https://get.docker.com | sh
# Add user to docker group — no sudo needed (takes effect after reboot)
usermod -aG docker $system_user_name
docker compose version

# ─── Lazydocker ───────────────────────────────────────────────────────────────
# TUI for Docker — browse containers, logs, images, volumes without typing commands 
curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash

# ─── kubectl (pkgs.k8s.io — packages.cloud.google.com is deprecated) ─────────
echo "Installing kubectl"
install -m 0755 -d /etc/apt/keyrings   # dir may not exist on a clean install
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list
apt update && apt install -y kubectl

# ─── Minikube ─────────────────────────────────────────────────────────────────
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube
minikube version

# ─── Golang ───────────────────────────────────────────────────────────────────
echo "Installing Go"
apt install -y golang

# ─── Node.js via NVM ──────────────────────────────────────────────────────────
# NVM is per-user (not system-wide) — must run as actual user, not root
echo "Installing NVM + Node LTS"
sudo -u $system_user_name bash -c \
  'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
sudo -u $system_user_name bash -c \
  'export NVM_DIR="$HOME/.nvm" && source "$NVM_DIR/nvm.sh" && nvm install --lts && nvm alias default node && npm install -g yarn pnpm'

# ─── PHP 8.3 via packages.sury.org ───────────────────────────────────────────
# Ubuntu 26.04 ships PHP 8.5; we pin 8.3 for Laravel. Ondřej's packages moved off
# the Launchpad PPA for 26.04+ — they now live on packages.sury.org (the PPA only
# publishes for <= 24.04).
echo "Installing PHP 8.3 + extensions"
curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
dpkg -i /tmp/debsuryorg-archive-keyring.deb
rm -f /tmp/debsuryorg-archive-keyring.deb
echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
  > /etc/apt/sources.list.d/php.list
apt update
# Extension notes (comments kept off '\'-continued lines on purpose, see essentials block):
#   bcmath ctype dom fileinfo mbstring tokenizer xml = Laravel core requirements
#   curl=HTTP client/HTTP facade   gd/imagick=image processing   gmp=bignum   intl=i18n/Carbon
#   mongodb/mysql/pgsql/sqlite3=DB drivers   opcache=bytecode cache   pdo=PDO base
#   readline=artisan tinker   redis=queues/cache/sessions   soap/xmlrpc/xsl=web services   zip=Composer
# Core + Laravel-required (must succeed)
apt install -y \
  php8.3 php8.3-cli php8.3-common \
  php8.3-bcmath php8.3-ctype php8.3-curl php8.3-dom php8.3-fileinfo \
  php8.3-gd php8.3-gmp php8.3-intl php8.3-mbstring \
  php8.3-mysql php8.3-opcache php8.3-pdo php8.3-pgsql \
  php8.3-readline php8.3-soap php8.3-sqlite3 php8.3-tokenizer \
  php8.3-xml php8.3-xsl php8.3-zip

# PECL-based — may lag on a brand-new LTS; install best-effort, warn if absent
for ext in php8.3-imagick php8.3-redis php8.3-mongodb php8.3-xmlrpc; do
  if ! apt install -y "$ext"; then
    echo "  ! ${ext} not available yet for this release — trying PECL / skipping."
  fi
done

# phpredis isn't in sury for 26.04 yet — build it from PECL so Laravel's redis driver
# works. (Alternative: use predis/predis, a pure-PHP client, and skip this entirely.)
if ! php -m 2>/dev/null | grep -qix redis; then
  echo "Building php-redis via PECL (apt package not yet available for this release)"
  if apt install -y php8.3-dev php-pear; then
    update-alternatives --set phpize /usr/bin/phpize8.3 2>/dev/null || true
    update-alternatives --set php-config /usr/bin/php-config8.3 2>/dev/null || true
    if yes '' | pecl install redis; then
      echo "extension=redis.so" > /etc/php/8.3/mods-available/redis.ini
      phpenmod -v 8.3 redis
    else
      echo "  ! PECL redis build failed — use predis/predis (pure PHP) in Laravel instead."
    fi
  else
    echo "  ! could not install php8.3-dev — skipping php-redis (use predis/predis)."
  fi
fi

# Ensure php8.3 is active CLI version (not 8.5 default)
update-alternatives --set php /usr/bin/php8.3
# Keep companion dev tools on 8.3 too (only registered once php8.3-dev is present —
# guarded no-op otherwise). Avoids a mixed 8.5/8.3 toolchain for phpize/pecl.
for _alt in phpize php-config phpdbg; do
  update-alternatives --set "$_alt" "/usr/bin/${_alt}8.3" 2>/dev/null || true
done

# ─── Xdebug ───────────────────────────────────────────────────────────────────
echo "Installing Xdebug"
apt install -y php8.3-xdebug

mkdir -p ${XDEBUG_DIR}
chown $system_user_name:$system_user_name ${XDEBUG_DIR}

# Xdebug 3 config:
#   xdebug.remote_enable dropped (Xdebug 2 legacy, xdebug.mode=debug covers it)
cat > /etc/php/8.3/mods-available/xdebug.ini <<EOF
zend_extension=xdebug
xdebug.client_port=9003
xdebug.var_display_max_children=-1
xdebug.mode=debug,develop,coverage,profile
xdebug.start_with_request=trigger
xdebug.idekey=VSCODE
xdebug.output_dir=${XDEBUG_DIR}
xdebug.profiler_output_name=cachegrind.out.%p
xdebug.profiler_append=0
xdebug.log_level=3
xdebug.cli_color=1
xdebug.log=${XDEBUG_DIR}/xdebug.log
EOF

phpenmod -v 8.3 xdebug

# ─── Composer ─────────────────────────────────────────────────────────────────
echo "Installing Composer"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
# Verify the installer against Composer's published SHA-384 before executing it
EXPECTED_COMPOSER_SIG="$(php -r "echo file_get_contents('https://composer.github.io/installer.sig');")"
if ! php -r "exit(hash_file('sha384','composer-setup.php') === '${EXPECTED_COMPOSER_SIG}' ? 0 : 1);"; then
  echo "Composer installer signature mismatch — aborting."
  php -r "unlink('composer-setup.php');"
  exit 1
fi
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer

# ─── PHPUnit 11 ───────────────────────────────────────────────────────────────
echo "Installing PHPUnit 11"
wget -O phpunit https://phar.phpunit.de/phpunit-11.phar
chmod +x phpunit
mv phpunit /usr/local/bin/phpunit

# ─── WP-CLI ───────────────────────────────────────────────────────────────────
echo "Installing WP-CLI"
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# ─── Apache ───────────────────────────────────────────────────────────────────
echo "Installing Apache"
apt install -y apache2 libapache2-mod-php8.3
mkdir -p ${USER_HOME}/web
cat > /etc/apache2/sites-available/000-default.conf <<EOF
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot ${USER_HOME}/web
  SetEnv APPLICATION_ENV "development"
  <Directory ${USER_HOME}/web>
    Options FollowSymLinks
    DirectoryIndex index.php index.html
    AllowOverride All
    Require all granted
  </Directory>
  ErrorLog \${APACHE_LOG_DIR}/error.log
  CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
a2enmod rewrite
# Set a global ServerName to silence the AH00558 FQDN warning (config is valid without it)
echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
a2enconf servername
apachectl configtest
systemctl restart apache2

# ─── MySQL ────────────────────────────────────────────────────────────────────
echo "Installing MySQL + creating 'admin' user"
apt install -y mysql-server
systemctl start mysql.service
# 'admin' local-dev user — password prompted at the start of this script.
# Piped over stdin (not -e) so the cleartext password never lands in process args.
mysql -u root <<SQL
CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY '${mysql_admin_pass}';
ALTER USER 'admin'@'localhost' IDENTIFIED BY '${mysql_admin_pass}';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# Note: a MongoDB *server* is not in the default Ubuntu repos — only the php8.3-mongodb
# driver and Compass GUI are installed here. Run a local Mongo via the Docker you
# installed earlier when you need one:
#   docker run -d --name mongo -p 27017:27017 mongo:latest

# ─── VS Code ──────────────────────────────────────────────────────────────────
echo "Installing VS Code"
install_deb_from_url "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" "VS Code"

# ─── SQLite3 + Browser ──────────────────────────────────────────────────────────────────
echo "SQLite3 + Browser"
apt install -y sqlite3
apt install -y sqlitebrowser

# ─── Beekeeper Studio ─────────────────────────────────────────────────────────
echo "Beekeeper Studio"
curl -fsSL https://deb.beekeeperstudio.io/beekeeper.key \
  | gpg --batch --yes --dearmor -o /usr/share/keyrings/beekeeper.gpg
echo "deb [signed-by=/usr/share/keyrings/beekeeper.gpg] https://deb.beekeeperstudio.io stable main" \
  | tee /etc/apt/sources.list.d/beekeeper-studio-app.list
apt update && apt install -y beekeeper-studio

# ─── MongoDB Compass ──────────────────────────────────────────────────────────
install_deb_from_url "https://downloads.mongodb.com/compass/mongodb-compass_1.49.7_amd64.deb" "MongoDB Compass"

# ─── Claude Code ──────────────────────────────────────────────────────────────
echo "Installing Claude Code"
sudo -u $system_user_name bash -c \
  'export NVM_DIR="$HOME/.nvm" && source "$NVM_DIR/nvm.sh" && npm install -g @anthropic-ai/claude-code'

# Plugins are NOT installed here. `claude plugin marketplace add` / `claude plugin
# install` are interactive-only (no --yes flag exists) and require `claude login`
# first, so they HANG in an unattended script. Install them once, interactively,
# after first login (see the post-reboot checklist). For reference:
#   claude plugin marketplace add anthropics/claude-plugins-official
#   claude plugin marketplace add thedotmack/claude-mem
#   claude plugin install ralph-loop@claude-plugins-official
#   claude plugin install superpowers@claude-plugins-official
#   claude plugin install frontend-design@claude-plugins-official
#   claude plugin install claude-mem@thedotmack

# ─── OpenAI Codex CLI ────────────────────────────────────────────────────────
echo "Installing Codex CLI"
sudo -u $system_user_name bash -c \
  'export NVM_DIR="$HOME/.nvm" && source "$NVM_DIR/nvm.sh" && npm install -g @openai/codex'

# ─── Gemini CLI ──────────────────────────────────────────────────────────────
# Google's terminal agent (generous free tier) — third CLI agent alongside Claude/Codex
echo "Installing Gemini CLI"
sudo -u $system_user_name bash -c \
  'export NVM_DIR="$HOME/.nvm" && source "$NVM_DIR/nvm.sh" && npm install -g @google/gemini-cli'

# ─── OpenCode ─────────────────────────────────────
# Git-aware AI coding tool; installed as an isolated uv tool (uv installed earlier)
echo "Installing OpenCode"
curl -fsSL https://opencode.ai/install | bash

# ─── Ollama — local LLM runtime ──────────────────────────────────────────────
# Runs models locally/offline (llama, qwen, deepseek…); sets up a systemd service.
# Pull a model afterwards, e.g.: ollama pull qwen2.5-coder
echo "Installing Ollama"
curl -fsSL https://ollama.com/install.sh | sh

# ─── Remove Snaps ─────────────────────────────────────────────────────────────
echo "Removing snaps"
systemctl disable snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
for pkg in firefox snap-store gnome-42-2204 gtk-common-themes snapd-desktop-integration bare core22 snapd; do
  snap remove --purge $pkg 2>/dev/null || true
done
rm -rf /var/cache/snapd/
apt autoremove -y --purge snapd
rm -rf ${USER_HOME}/snap
cat > /etc/apt/preferences.d/nosnap.pref <<EOF
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

# ─── GNOME Software (Flatpak, no snap) ───────────────────────────────────────
echo "Installing GNOME Software"
apt install -y --install-suggests gnome-software

# ─── Flatpak ──────────────────────────────────────────────────────────────────
echo "Setting up Flatpak + Flathub"
apt install -y flatpak gnome-software-plugin-flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# ─── Flatpak Apps ─────────────────────────────────────────────────────────────
echo "Installing Flatpak apps"
flatpak install -y --noninteractive flathub io.github.shiftey.Desktop   # GitHub Desktop
flatpak install -y --noninteractive flathub com.discordapp.Discord
flatpak install -y --noninteractive flathub md.obsidian.Obsidian         # Notes/wiki/docs
flatpak install -y --noninteractive flathub com.usebruno.Bruno           # API client (replaces Insomnia)
flatpak install -y --noninteractive flathub chat.rocket.RocketChat       # Team chat
flatpak install -y --noninteractive flathub org.signal.Signal            # Signal messenger
flatpak install -y --noninteractive flathub org.telegram.desktop         # Telegram
flatpak install -y --noninteractive flathub com.spotify.Client           # Spotify

# ─── Google Chrome ────────────────────────────────────────────────────────────
install_deb_from_url "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" "Google Chrome"

# ─── Brave Browser ────────────────────────────────────────────────────────────
echo "Installing Brave"
curl -fsS https://dl.brave.com/install.sh | sh

# ─── Firefox (APT, not snap) ──────────────────────────────────────────────────
echo "Installing Firefox (APT, not snap)"
add-apt-repository -y ppa:mozillateam/ppa
cat > /etc/apt/preferences.d/mozilla-firefox <<EOF
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF
echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:${distro_codename}";' \
  | tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
apt install -y firefox

# ─── Firefox privacy hardening (practical) ───────────────────────────────────
# Two layers:
#  1) policies.json — system-wide, profile-independent kill-switches (telemetry,
#     studies, Pocket, sponsored content, tracking protection, DoH). Apt Firefox
#     reads /etc/firefox/policies/policies.json.
#  2) user.js — curated per-profile prefs. Deeper privacy WITHOUT breaking daily
#     use: cookies/logins, password manager, WebRTC and dark mode all stay working
#     (resistFingerprinting deliberately left OFF — it letterboxes the window and
#     breaks timezone/dark-mode detection).
echo "Hardening Firefox (privacy)"

# --- Layer 1: system-wide enterprise policy ---
mkdir -p /etc/firefox/policies
cat > /etc/firefox/policies/policies.json <<'EOF'
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "EnableTrackingProtection": {
      "Value": true,
      "Cryptomining": true,
      "Fingerprinting": true
    },
    "FirefoxHome": {
      "Pocket": false,
      "SponsoredPocket": false,
      "SponsoredTopSites": false,
      "Snippets": false
    },
    "UserMessaging": {
      "ExtensionRecommendations": false,
      "FeatureRecommendations": false,
      "UrlbarInterventions": false,
      "SkipOnboarding": true
    },
    "DNSOverHTTPS": { "Enabled": true },
    "DontCheckDefaultBrowser": true
  }
}
EOF

# --- Layer 2: curated user.js, staged in HOME then copied into the profile ---
# Staging copy (kept so you can re-apply to any profile later).
sudo -u $system_user_name tee "${USER_HOME}/firefox-user.js" >/dev/null <<'EOF'
// Curated practical privacy prefs — privacy without breaking daily use.
// Telemetry & data reporting
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.coverage.opt-out", true);
user_pref("toolkit.coverage.opt-out", true);
user_pref("toolkit.coverage.endpoint.base", "");
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
// Studies / experiments / Normandy
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("app.normandy.api_url", "");
// Crash reports
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);
// Pocket
user_pref("extensions.pocket.enabled", false);
// New tab page: no sponsored/recommended content or telemetry
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.ping-centre.telemetry", false);
// Address-bar: keep search, drop sponsored / quick-suggest
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
user_pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
// about:addons recommendations
user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("browser.discovery.enabled", false);
// Tracking protection — strict
user_pref("browser.contentblocking.category", "strict");
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
// Cookies — block cross-site trackers + partition 3rd-party (logins still work)
user_pref("network.cookie.cookieBehavior", 5);
// Lightweight fingerprinting protection (RFP-lite; far less breaky than resistFingerprinting)
user_pref("privacy.fingerprintingProtection", true);
// Referrers — trim cross-origin referrer to the origin
user_pref("network.http.referer.XOriginTrimmingPolicy", 2);
// HTTPS-only mode
user_pref("dom.security.https_only_mode", true);
// DNS-over-HTTPS (mode 2 = use DoH, fall back to system DNS on failure)
user_pref("network.trr.mode", 2);
// Reduce background network chatter
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);
user_pref("browser.urlbar.speculativeConnect.enabled", false);
// Misc
user_pref("beacon.enabled", false);
user_pref("geo.enabled", false);
user_pref("extensions.formautofill.addresses.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);
// Intentionally left at defaults to avoid breakage:
//   cookies persist (stay logged in), password manager on, WebRTC on,
//   resistFingerprinting OFF, history kept.
EOF
chown $system_user_name:$system_user_name "${USER_HOME}/firefox-user.js"

# Firefox creates its profile on first run — do a headless first-run to generate it,
# then copy user.js into the default profile. Best-effort: never aborts the script.
sudo -u $system_user_name timeout 25 firefox --headless --first-startup about:blank >/dev/null 2>&1 || true
FF_PROFILE=$(sudo -u $system_user_name bash -c 'ls -d "$HOME"/.mozilla/firefox/*.default-release 2>/dev/null | head -n1')
[[ -z "$FF_PROFILE" ]] && FF_PROFILE=$(sudo -u $system_user_name bash -c 'ls -d "$HOME"/.mozilla/firefox/*.default 2>/dev/null | head -n1')
if [[ -n "$FF_PROFILE" ]]; then
  sudo -u $system_user_name cp "${USER_HOME}/firefox-user.js" "${FF_PROFILE}/user.js"
  echo "  Applied user.js to ${FF_PROFILE}"
else
  echo "  ! No Firefox profile found yet — launch Firefox once, then:"
  echo "      cp ${USER_HOME}/firefox-user.js <profile-dir>/user.js"
fi

# ─── Media ────────────────────────────────────────────────────────────────────
echo "Installing media apps (vlc, ffmpeg, obs, qbittorrent)"
apt install -y vlc ffmpeg obs-studio mediainfo mediainfo-gui qbittorrent

# ─── Laptop & Thinkpad specific ──────────────────────────────────────────────────
if [[ -f /sys/module/battery/initstate ]] || [[ -d /proc/acpi/battery/BAT0 ]]; then
  echo "Battery detected — installing TLP + powertop"
  apt install -y tlp tlp-rdw powertop

  # acpi-call lets TLP set charge thresholds
  # (tp-smapi is for older ThinkPads)
  if grep -qi "thinkpad" /sys/devices/virtual/dmi/id/product_family 2>/dev/null; then
    echo "ThinkPad detected — installing acpi-call for charge threshold control"
    apt install -y acpi-call-dkms
    # Start charging at 40%, stop at 80% — good for plugged-in daily use
    # Edit /etc/tlp.conf to adjust thresholds
    cat >> /etc/tlp.conf <<EOF

# ThinkPad battery charge thresholds
START_CHARGE_THRESH_BAT0=40
STOP_CHARGE_THRESH_BAT0=95
EOF
  fi

  tlp start
fi

# ─── Disable Error Reporting ─────────────────────────────────────────────────
apt purge -y apport

# Opt out of the Ubuntu install report FIRST, while metrics.ubuntu.com is still
# reachable. Doing it after the blackhole below makes it POST to 127.0.0.1:443 and
# log a (harmless) "connection refused". || true so no-network can't abort the run.
echo "Opting out of Ubuntu telemetry (ubuntu-report)"
ubuntu-report -f send no || true

echo "Blackholing Ubuntu metrics/popcon hosts"
for _h in www.metrics.ubuntu.com metrics.ubuntu.com www.popcon.ubuntu.com popcon.ubuntu.com; do
  grep -qxF "127.0.0.1 $_h" /etc/hosts || echo "127.0.0.1 $_h" >>/etc/hosts
done

# ─── tmux config ─────────────────────────────────────────────────────────────
echo "Writing tmux config"
cat > ${USER_HOME}/.tmux.conf <<'EOF'
# ─── General ──────────────────────────────────────────────────────────────────
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"   # true colour support
set -g history-limit 10000                          # scrollback buffer
set -g mouse on                                     # mouse scrolling, pane click, resize
set -g base-index 1                                 # windows start at 1 (not 0)
setw -g pane-base-index 1                           # panes start at 1
set -g renumber-windows on                          # renumber windows after closing one
set -sg escape-time 0                               # no escape key delay (critical for vim/neovim)
set -g focus-events on                              # pass focus events to apps (vim autoread)

# ─── Prefix ───────────────────────────────────────────────────────────────────
# Default prefix is Ctrl+B — uncomment below to change to Ctrl+A (screen-style)
# unbind C-b
# set -g prefix C-a
# bind C-a send-prefix

# ─── Splits ───────────────────────────────────────────────────────────────────
bind | split-window -h -c "#{pane_current_path}"   # vertical split, same dir
bind - split-window -v -c "#{pane_current_path}"   # horizontal split, same dir
unbind '"'
unbind %

# ─── Pane Navigation ──────────────────────────────────────────────────────────
# Vim-style with prefix
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Alt+Arrow without prefix (convenient for quick switching)
bind -n M-Left  select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up    select-pane -U
bind -n M-Down  select-pane -D

# ─── Window Navigation ────────────────────────────────────────────────────────
bind -n S-Left  previous-window
bind -n S-Right next-window

# ─── Vi Copy Mode ─────────────────────────────────────────────────────────────
set-window-option -g mode-keys vi
bind -T copy-mode-vi v send-keys -X begin-selection
bind -T copy-mode-vi y send-keys -X copy-selection-and-cancel
bind -T copy-mode-vi r send-keys -X rectangle-toggle

# ─── Status Bar ───────────────────────────────────────────────────────────────
set -g status-position bottom
set -g status-style                 'bg=colour235,fg=colour250'
set -g status-left                  '#[fg=colour233,bg=colour241,bold] #S '
set -g status-right                 '#[fg=colour233,bg=colour241] %a %d %b  %H:%M '
set -g status-right-length 50
set -g status-left-length 20

setw -g window-status-current-style 'fg=colour81,bg=colour238,bold'
setw -g window-status-current-format ' #I:#W '
setw -g window-status-style         'fg=colour138,bg=colour235'
setw -g window-status-format        ' #I:#W '

# ─── Pane Borders ─────────────────────────────────────────────────────────────
set -g pane-border-style        'fg=colour238'
set -g pane-active-border-style 'fg=colour81'

# ─── Reload Config ────────────────────────────────────────────────────────────
bind r source-file ~/.tmux.conf \; display "tmux.conf reloaded!"
EOF
chown $system_user_name:$system_user_name ${USER_HOME}/.tmux.conf

# ─── Document Templates ──────────────────────────────────────────────────────
# Run as the user so files aren't root-owned (right-click → New Document menu)
echo "Creating document templates"
sudo -u $system_user_name mkdir -p ${USER_HOME}/Templates
sudo -u $system_user_name touch \
      ${USER_HOME}/Templates/text.txt \
      ${USER_HOME}/Templates/index.html \
      ${USER_HOME}/Templates/app.js \
      ${USER_HOME}/Templates/style.css \
      ${USER_HOME}/Templates/script.sh \
      ${USER_HOME}/Templates/template.yaml \
      ${USER_HOME}/Templates/compose.yaml \
      ${USER_HOME}/Templates/Dockerfile \
      ${USER_HOME}/Templates/.env

# ─── Swap File (8GB) ─────────────────────────────────────────────────────────
echo "Creating 8GB swap file"
swapoff -a
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
[[ -f /etc/fstab.orig ]] || cp /etc/fstab /etc/fstab.orig   # back up once, don't clobber on rerun
grep -qxF '/swapfile none swap sw 0 0' /etc/fstab || echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
free -m

# ─── ZSH + Oh My Zsh (robbyrussell) ─────────────────────────────────────────
echo "Installing ZSH + Oh My Zsh"
apt install -y zsh
chsh -s "$(which zsh)" $system_user_name

sudo -u $system_user_name sh -c \
  "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

ZSH_CUSTOM="${USER_HOME}/.oh-my-zsh/custom"

sudo -u $system_user_name git clone https://github.com/zsh-users/zsh-autosuggestions \
  ${ZSH_CUSTOM}/plugins/zsh-autosuggestions        # fish-style inline suggestions from history
sudo -u $system_user_name git clone https://github.com/zsh-users/zsh-syntax-highlighting \
  ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting    # colours valid/invalid commands as you type

# Built-in plugins: git, docker, docker-compose, kubectl, nvm provide aliases + completions
sed -i 's/^plugins=(git)/plugins=(git docker docker-compose kubectl nvm zsh-autosuggestions zsh-syntax-highlighting)/' \
  ${USER_HOME}/.zshrc

cat >> ${USER_HOME}/.zshrc <<'ZSHEOF'

# ── PATH ──────────────────────────────────────────────────────────────────────
# ~/.local/bin holds uv + our bat/fd symlinks; Composer global tools (laravel/installer,
# pint, pest) install under ~/.config/composer/vendor/bin
export PATH="$HOME/.local/bin:$HOME/.config/composer/vendor/bin:$PATH"

# ── Aliases ───────────────────────────────────────────────────────────────────
# Safe aliases — only replacing interactive display tools, not system utilities
alias ls='eza --icons'              # eza: modern ls with icons
alias ll='eza -la --icons --git'    # long list + hidden files + git status
alias cat='bat'                     # bat: cat with syntax highlighting

# ── Tools init ────────────────────────────────────────────────────────────────
# zoxide — replaces cd, must init after compinit
eval "$(zoxide init zsh)"

# uv shell completions
eval "$(uv generate-shell-completion zsh)"
ZSHEOF

chown $system_user_name:$system_user_name ${USER_HOME}/.zshrc

# ─── Cleanup ──────────────────────────────────────────────────────────────────
apt autoclean -y && apt autoremove -y && apt clean -y

echo ""
echo "Done! Please reboot."
echo ""
echo "Post-reboot checklist:"
echo "  - GNOME tweaks: run ./gnome-tweak.sh as your normal user (NOT sudo)"
echo "  - Docker without sudo: active after reboot (group: docker)"
echo "  - ThinkPad charge thresholds: sudo tlp-stat --battery"
echo "  - Xdebug output dir: ${XDEBUG_DIR}"
echo "  - tmux: prefix+r reloads config | prefix+| vertical | prefix+- horizontal"
echo "  - Claude Code: 'claude' to log in, THEN install plugins (interactive, can't be scripted):"
echo "      claude plugin marketplace add anthropics/claude-plugins-official"
echo "      claude plugin marketplace add thedotmack/claude-mem"
echo "      claude plugin install ralph-loop@claude-plugins-official"
echo "      claude plugin install superpowers@claude-plugins-official"
echo "      claude plugin install frontend-design@claude-plugins-official"
echo "      claude plugin install claude-mem@thedotmack"
echo "  - MySQL: user 'admin' with the password you entered"
echo "  - bat/fd: linked to ~/.local/bin (set your terminal font to 'FiraCode Nerd Font')"
echo "  - AI CLIs: run 'claude' / 'codex' / 'gemini' to authenticate; aider via 'aider'"
echo "  - Ollama: pull a model, e.g. 'ollama pull qwen2.5-coder'"
echo "  - Timeshift: open it once to configure snapshot schedule + location"
echo "  - mkcert: 'mkcert myapp.test' generates a trusted local HTTPS cert for Apache vhosts"
echo "  - Firefox: privacy policies applied system-wide; verify prefs at about:policies"
echo "    and about:config. If no profile existed at install, apply ~/firefox-user.js"
echo "    by copying it into your profile dir as user.js (see about:profiles)."
exit 0