#!/bin/bash

apt-get -y install python-software-properties
apt-add-repository -y ppa:brightbox/ruby-ng
apt-get -y update
apt-get -y install ruby2.6 ruby2.6-dev
gem install bundler --no-document
