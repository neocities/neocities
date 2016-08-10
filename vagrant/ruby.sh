#!/bin/bash

apt-get -y install python-software-properties
apt-add-repository -y ppa:brightbox/ruby-ng
apt-get -y update
apt-get -y install ruby2.3 ruby2.3-dev
gem install bundler --no-rdoc --no-ri
