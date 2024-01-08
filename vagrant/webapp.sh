#!/bin/bash

DEBIAN_FRONTEND=noninteractive

. /vagrant/vagrant/redis.sh

apt-get install -y \
  build-essential \
  clamav-daemon \
  curl \
  file \
  git \
  imagemagick \
  libcurl4-openssl-dev \
  libffi-dev \
  libimlib2-dev \
  libmagic-dev \
  libmagickwand-dev \
  libpq-dev \
  libreadline-dev \
  libsqlite3-dev \
  libssl-dev \
  libwebp-dev \
  libxml2-dev \
  libxslt1-dev \
  libyaml-dev \
  sqlite3 \
  zlib1g-dev

sed -i 's|[#]*DetectPUA false|DetectPUA true|g' /etc/clamav/clamd.conf

#sudo freshclam
#sudo systemctl start clamav-freshclam

# clamav download mirrors have insanely stupid limits so we just put in a github mirror for now
rm -f main.cvd daily.cld daily.cvd bytecode.cvd main.cvd.sha256 daily.cvd.sha256 bytecode.cvd.sha256 main.cvd.* daily.cvd.* && curl -LSOs https://github.com/ladar/clamav-data/raw/main/main.cvd.[01-10] -LSOs https://github.com/ladar/clamav-data/raw/main/main.cvd.sha256 -LSOs https://github.com/ladar/clamav-data/raw/main/daily.cvd.[01-10] -LSOs https://github.com/ladar/clamav-data/raw/main/daily.cvd.sha256 -LSOs https://github.com/ladar/clamav-data/raw/main/bytecode.cvd -LSOs https://github.com/ladar/clamav-data/raw/main/bytecode.cvd.sha256 && cat main.cvd.01 main.cvd.02 main.cvd.03 main.cvd.04 main.cvd.05 main.cvd.06 main.cvd.07 main.cvd.08 main.cvd.09 main.cvd.10 > main.cvd && cat daily.cvd.01 daily.cvd.02 daily.cvd.03 daily.cvd.04 daily.cvd.05 daily.cvd.06 daily.cvd.07 daily.cvd.08 daily.cvd.09 daily.cvd.10 > daily.cvd && sha256sum -c main.cvd.sha256 daily.cvd.sha256 bytecode.cvd.sha256 || { printf "ClamAV database download failed.\n" ; rm -f main.cvd daily.cvd bytecode.cvd ; } ; rm -f main.cvd.sha256 daily.cvd.sha256 bytecode.cvd.sha256 main.cvd.* daily.cvd.* && sudo mv *.cvd /var/lib/clamav/


sudo systemctl enable clamav-daemon
sudo systemctl start clamav-daemon
usermod -G vagrant clamav

cd /vagrant
bundle install
