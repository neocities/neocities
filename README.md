# Neocities.org

[![Build Status](https://travis-ci.org/neocities/neocities.png?branch=master)](https://travis-ci.org/neocities/neocities)
[![Coverage Status](https://coveralls.io/repos/neocities/neocities/badge.svg?branch=master&service=github)](https://coveralls.io/github/neocities/neocities?branch=master)

The web site for Neocities! It's open source. Want a feature on the site? Send a pull request!

## Getting Started

Neocities can be quickly launched in development mode with [Vagrant](https://www.vagrantup.com). Vagrant builds a virtual machine that automatically installs everything you need to run Neocities as a developer. Install Vagrant, then from the command line:

```
vagrant up --provision
```

![Vagrant takes a while, make a pizza while waiting](http://i.imgur.com/vfIJPXP.png)

```
vagrant ssh
cd /vagrant
bundle exec rackup -o 0.0.0.0
```

Now you can access the running site from your browser: http://127.0.0.1:9292

## Want to contribute?

If you'd like to fix a bug, or make an improvement, or add a new feature, it's easy! Just send us a Pull Request.

1. Fork it (<http://github.com/YOURUSERNAME/neocities/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
