#!/bin/bash

DEBIAN_FRONTEND=noninteractive

. /vagrant/vagrant/phantomjs.sh
. /vagrant/vagrant/redis.sh

apt-get install -y git curl zlib1g-dev build-essential libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev libffi-dev libpq-dev libmagickwand-dev imagemagick libmagickwand-dev libmagic-dev file clamav-daemon

sed -i 's|[#]*DetectPUA false|DetectPUA true|g' /etc/clamav/clamd.conf

freshclam
service clamav-freshclam start
service clamav-daemon start

usermod -G vagrant clamav

cd /vagrant
bundle install