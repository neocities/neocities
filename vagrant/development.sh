#!/bin/bash

DEBIAN_FRONTEND=noninteractive
. /vagrant/vagrant/common.sh
. /vagrant/vagrant/database.sh
. /vagrant/vagrant/ruby.sh
. /vagrant/vagrant/webapp.sh

ufw allow 9292

sudo su postgres -c "createuser -d vagrant"
sudo su vagrant -c "createdb neocities"
sudo su vagrant -c "createdb neocities_test"

sudo sh -c 'echo "local all postgres trust" > /etc/postgresql/9.3/main/pg_hba.conf'
sudo sh -c 'echo "local all all trust" >> /etc/postgresql/9.3/main/pg_hba.conf'
sudo sh -c 'echo "host all all 127.0.0.1/32 trust" >> /etc/postgresql/9.3/main/pg_hba.conf'
sudo sh -c 'echo "host all all ::1/128 trust" >> /etc/postgresql/9.3/main/pg_hba.conf'
sudo service postgresql restart
