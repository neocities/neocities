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