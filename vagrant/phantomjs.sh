#!/bin/bash

DEBIAN_FRONTEND=noninteractive

wget https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-1.9.8-linux-x86_64.tar.bz2
bzip2 -dc phantomjs-1.9.8-linux-x86_64.tar.bz2 | tar xf -
cp phantomjs-1.9.8-linux-x86_64/bin/phantomjs /usr/local/bin/