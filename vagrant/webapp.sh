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

freshclam
service clamav-freshclam start
service clamav-daemon start

usermod -G vagrant clamav

cd /vagrant
bundle install
