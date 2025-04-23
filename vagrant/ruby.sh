#!/bin/bash

sudo apt-get -y install autoconf patch build-essential rustc libssl-dev libyaml-dev libreadline6-dev zlib1g-dev libgmp-dev libncurses5-dev libffi-dev libgdbm6 libgdbm-dev libdb-dev uuid-dev

wget https://cache.ruby-lang.org/pub/ruby/3.3/ruby-3.3.0.tar.gz
gzip -dc ruby-3.3.0.tar.gz | tar xf -
cd ruby-3.3.0
./autogen.sh
./configure --enable-yjit --disable-install-doc
make -j && sudo make install
cd ..
