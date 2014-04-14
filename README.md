# NeoCities.org

[![Build Status](https://travis-ci.org/neocities/neocities.png?branch=master)](https://travis-ci.org/neocities/neocities)

The web site for NeoCities! It's open source. Want a feature on the site? Send a pull request!

## Installation (OSX)

Install homebrew:
```
ruby -e "$(curl -fsSL https://raw.github.com/Homebrew/homebrew/go/install)"
```

Install deps:
```
$ brew install redis postgresql phantomjs libmagic imagemagick
```

Fork the repository on Github.
Clone the forked repo to your local machine: git clone git@github.com:YOURUSERNAME/neocities.git
Install deps:

```
$ cd neocities
$ gem install bundler
$ bundle install
```

Create postgres databases:

```
createdb neocities_test
createdb neocities_dev
```

Copy config.yml.template to config.yml and edit to something like this:
```
  development:
    database: 'postgres://neocities@127.0.0.1/neocities_dev'
    database_pool: 1
    session_secret: SECRET1234
    recaptcha_public_key: ENTER RECAPTCHA PUBLIC KEY HERE
    recaptcha_private_key: ENTER RECAPTCHA PRIVATE KEY HERE
    sidekiq_user: sidekiq
    sidekiq_pass: sidekiq
    phantomjs_url:
      - http://localhost:8910
```

Run the tests to see if they work:

```
  bundle exec rake test
```

## Want to contribute?

If you'd like to fix a bug, or make an improvement, or add a new feature, it's easy! Just send us a Pull Request.

1. Fork it ( http://github.com/<my-github-username>/neocities/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request