# Quiets the TTY error message
#sed -i 's/^mesg n$/tty -s \&\& mesg n/g' /root/.profile

DEBIAN_FRONTEND=noninteractive

apt-get -y update
apt-get -y upgrade
apt-get install -y openntpd htop autossh sshfs vim

echo 'UTC' | tee /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

update-alternatives --set editor /usr/bin/vim.basic

ufw allow ssh
ufw --force enable
ufw logging off

sed -i 's|[#]*PasswordAuthentication yes|PasswordAuthentication no|g' /etc/ssh/sshd_config
sed -i 's|UsePAM yes|UsePAM no|g' /etc/ssh/sshd_config
#sed -i 's|[#]*PermitRootLogin yes|PermitRootLogin no|g' /etc/ssh/sshd_config

service ssh restart


wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i google-chrome-stable_current_amd64.deb
sudo apt-get install -f -y
rm google-chrome-stable_current_amd64.deb
