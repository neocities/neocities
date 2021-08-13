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

sudo sh -c 'echo "local all postgres trust" > /etc/postgresql/10/main/pg_hba.conf'
sudo sh -c 'echo "local all all trust" >> /etc/postgresql/10/main/pg_hba.conf'
sudo sh -c 'echo "host all all 127.0.0.1/32 trust" >> /etc/postgresql/10/main/pg_hba.conf'
sudo sh -c 'echo "host all all ::1/128 trust" >> /etc/postgresql/10/main/pg_hba.conf'
sudo systemctl restart postgresql

# Create empty file for disposable email accounts
DISPOSABLE_EMAIL_PATH=/vagrant/files/disposable_email_blacklist.conf
if [ ! -f $DISPOSABLE_EMAIL_PATH ]; then
    sudo su vagrant -c "touch $DISPOSABLE_EMAIL_PATH"
fi

# Automatically enter the project path on vagrant ssh
if grep -qv "cd /vagrant" /home/vagrant/.bashrc
then
    sudo su vagrant -c "echo 'cd /vagrant' >> ~/.bashrc"
fi

