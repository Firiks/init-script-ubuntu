#!/bin/bash
# Post install script for debian/ubuntu based distros with gnome DE, run only on clean install !!!

set -e

if [[ $EUID -ne 0 ]]; then
  echo "This script must be ran with root privileges"
  exit 1
fi

echo "System user name?"
read -e system_user_name

echo "GIT user.name?"
read -e git_config_user_name

echo "GIT user.email?"
read -e git_config_user_email

# change workdir to downloads
echo "Changing dir to Downloads"
cd /home/${system_user_name}/Downloads

# update
echo "Updating system"
apt update && apt dist-upgrade -y && apt upgrade -y && apt autoremove -y && apt autoclean -y

# CPU microcode
vendor=$(lscpu | awk '/Vendor ID/{print $3}')
if [[ "$vendor" == "GenuineIntel" ]]; then
  echo "Intel cpu, Installing microcode"
  apt install -y intel-microcode
elif [[ "$vendor" == "AuthenticAMD" ]]; then
  echo "AMD cpu, Installing microcode"
  apt install -y amd64-microcode
else
  echo "cpu vendor: $vendor should be microcode installed ?"
fi

# restricted extras
echo "Installing Ubuntu Restricted Extras"
apt install -y ubuntu-restricted-extras

# essential packages & utils
echo "Installing essential & utils"
apt install -y software-properties-common apt-transport-https ca-certificates lsb-release gnupg wget curl net-tools network-manager-openvpn network-manager-openconnect-gnome synaptic gnome-shell-extensions gnome-tweaks chrome-gnome-shell tldr xclip htop terminator neofetch gdebi gdebi-core cmatrix trash-cli speedtest-cli gparted stow chkservice ncdu glances bleachbit awscli wavemon keepass2

# python
echo "Installing python enviroment"
apt install -y python3-pip
apt install -y build-essential libssl-dev libffi-dev python3-dev
apt install -y python3-venv

# install java
echo "Installing Open JDK 11"
apt install -y default-jre
java -version

# openssh client
echo "Installing openssh client"
apt install -y openssh-client

# SSH gui tool
echo "Installing snowflake"
wget -O snowflake.deb https://github.com/subhra74/snowflake/releases/download/v1.0.4/snowflake-1.0.4-setup-amd64.deb
gdebi -n snowflake.deb

# guif ufw
echo "Installing gufw"
apt install -y gufw
# Enable Firewall
ufw enable

# extractors
echo "Installing extractors"
apt install -y unace rar unrar zip unzip p7zip-full p7zip-rar sharutils uudeview mpack arj cabextract file-roller

# android tools
echo "Installing adb & fastboot"
apt install -y android-tools-adb android-tools-fastboot

# git
echo "Installing git"
apt -y install git
git config --global user.name "$git_config_user_name"
git config --global user.email $git_config_user_email

# subversion
echo "Installing subversion"
apt install -y subversion

# Docker
echo "Installing Docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Docker compose
echo "Installing Docker compose"
curl -L "https://github.com/docker/compose/releases/download/v2.15.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Kubeclt
echo "Installing Kubeclt"
curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt update
apt install -y kubectl

# Minikube
echo "Installing minikube"
wget https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
cp minikube-linux-amd64 /usr/local/bin/minikube
chmod +x /usr/local/bin/minikube
minikube version

# Golang
echo "Installing golang"
apt install -y golang

# Nodejs
echo "Installing nodejs"
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt install -y nodejs
apt install -y gcc g++ make
npm update -g npm
npm install -g yarn gulp

# PHP & modules
echo "Installing PHP & modules"
apt install -y php8.1 # --no-install-recommends # uncoment to prevent apache2 install
apt install -y php8.1-cli php8.1-common php8.1-zip php8.1-mysql php8.1-mongodb php8.1-sqlite3 php8.1-xsl php8.1-pgsql php8.1-curl php8.1-gd php8.1-gmp php8.1-imagick php8.1-bcmath php8.1-intl php8.1-mbstring php8.1-soap php8.1-xml php8.1-xmlrpc php8.1-ssh2 php8.1-opcache php8.1-tokenizer php8.1-imap php8.1-fileinfo php8.1-readline

# Composer
echo "Installing composer"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer

# PHPUnit
wget -O phpunit https://phar.phpunit.de/phpunit-9.phar
chmod +x phpunit
mv phpunit /usr/local/bin/phpunit

# Xdebug
echo "Installing Xdebug"
apt install -y php-xdebug
# TODO: config
# [XDebug]
# zend_extension=xdebug.so
# xdebug.mode=debug,develop
# xdebug.client_port=9003
# xdebug.start_with_request=yes
# xdebug.client_host=host.local
# xdebug.log="/var/log/nginx/xdebug.log"
# xdebug.idekey=XDEBUG_ECLIPSE # default for extensions
# xdebug.discover_client_host=false
# xdebug.start_with_request=trigger

# WP-cli
echo "Echo installing WP-cli"
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Nginx
# echo "Installing NGINX"
# apt install -y nginx php8.1-fpm

# Apache - change USER_NAME to your user name
echo "Installing Apache"
apt install apache2 libapache2-mod-php8.1
mkdir /home/${system_user_name}/web
echo '
<VirtualHost *:80>
  ServerAdmin webmaster@localhost
  DocumentRoot /home/USER_NAME/web
  SetEnv APPLICATION_ENV "development"
  <Directory /home/USER_NAME/web>
    Options Indexes FollowSymLinks
    DirectoryIndex index.php
    AllowOverride All
    Require all granted
  </Directory>

  ErrorLog ${APACHE_LOG_DIR}/error.log
  CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>' > /etc/apache2/sites-available/000-default.conf
a2enmod rewrite
systemctl restart apache2

# Mysql
echo "Installing MYSQL"
apt install -y mysql-server
systemctl start mysql.service
mysql -u root -e "CREATE USER 'admin'@'localhost' IDENTIFIED BY 'admin123';"
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost';"
mysql -u root -e "FLUSH PRIVILEGES;"

# Vscode
echo "Installing vscode"
wget -O vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
gdebi -n vscode.deb

# Sqlite3
echo "Installing Sqlite3"
apt install -y sqlite3

# Beekeeper studio
echo "Installing Beekeeper Studio"
wget --quiet -O - https://deb.beekeeperstudio.io/beekeeper.key | apt-key add -
echo "deb https://deb.beekeeperstudio.io stable main" | tee /etc/apt/sources.list.d/beekeeper-studio-app.list
apt update -y
apt install -y beekeeper-studio

# Compass
echo "Installing MongoDB Compass"
wget -O compass.deb https://downloads.mongodb.com/compass/mongodb-compass_1.35.0_amd64.deb
gdebi -n compass.deb

# Remove snaps
echo "Removing snaps"
systemctl disable snapd.service
systemctl disable snapd.socket
systemctl disable snapd.seeded.service
snap remove --purge firefox
snap remove --purge snap-store
snap remove --purge gnome-3-38-2004
snap remove --purge gtk-common-themes
snap remove --purge snapd-desktop-integration
snap remove --purge bare
snap remove --purge core20
snap remove --purge snapd
rm -rf /var/cache/snapd/
apt autoremove -y --purge snapd
rm -rf /home/${system_user_name}/snap
echo '
Package: snapd
Pin: release a=*
Pin-Priority: -10
' > /etc/apt/preferences.d/nosnap.pref

# Gnome store
echo "Installing gnome store"
apt install -y --install-suggests gnome-software

# Flatpak
echo "Installing flatpak"
apt -y install flatpak
apt -y install gnome-software-plugin-flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
apt install -y gnome-software-plugin-flatpak

# Flaptak apps
echo "Installing flatpak apps"
flatpak install -y --noninteractive flathub rest.insomnia.Insomnia
flatpak install -y --noninteractive flathub chat.rocket.RocketChat
flatpak install -y --noninteractive flathub io.github.shiftey.Desktop
flatpak install -y --noninteractive flathub com.discordapp.Discord

# CrossFTP
echo "Installing CrossFTP"
wget -O crossftp.deb http://www.crossftp.com/crossftp_1.99.9.deb
gdebi -n crossftp.deb

# google chrome
echo "Installing chrome"
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
gdebi -n google-chrome-stable_current_amd64.deb

# firefox
echo "Installing apt firefox"
add-apt-repository ppa:mozillateam/ppa
echo '
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | tee /etc/apt/preferences.d/mozilla-firefox
echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:${distro_codename}";' | tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
apt install -y firefox

# media
echo "Installing media software"
apt -y install vlc ffmpeg obs-studio mediainfo mediainfo-gui qbittorrent

# laptop stuff
if [[ -f /sys/module/battery/initstate ]] || [[ -d /proc/acpi/battery/BAT0 ]]; then
  echo "Installing laptop tweaks"
  apt -y install tlp tlp-rdw
  tlp start
else
  echo "No battery"
fi

# disable error reporting
echo "Removing apport"
apt purge apport -y

# gnome tweaks
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize' # turn on “minimize on click”

# new document templates
echo "Creating document templates apport"
touch /home/${system_user_name}/Templates/text.txt
touch /home/${system_user_name}/Templates/index.html
touch /home/${system_user_name}/Templates/app.js
touch /home/${system_user_name}/Templates/style.css
touch /home/${system_user_name}/Templates/script.sh
touch /home/${system_user_name}/Templates/template.yaml
touch /home/${system_user_name}/Templates/document

# swap file
echo "Creating swap file"
swapoff -a
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
free -m

# cleanup
echo "Cleanup"
apt -y autoclean
apt -y autoremove
apt -y clean

echo 'Done! Please reboot your pc.'

exit 0