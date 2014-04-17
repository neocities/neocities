source 'https://rubygems.org'

gem 'sinatra'
gem 'redis'
gem 'sequel'
gem 'slim'
gem 'bcrypt'
gem 'sinatra-flash',      require: 'sinatra/flash'
gem 'sinatra-xsendfile',  require: 'sinatra/xsendfile'
gem 'puma',               require: nil
gem 'rubyzip',            require: 'zip'
gem 'rack-recaptcha',     require: 'rack/recaptcha'
gem 'rmagick',            require: nil
gem 'selenium-webdriver', require: nil
gem 'sidekiq'
gem 'ago'
gem 'mail'
gem 'google-api-client',  require: 'google/api_client'
gem 'tilt'

platform :mri do
  gem 'magic' # sudo apt-get install file, For OSX: brew install libmagic
  gem 'pg'
  gem 'sequel_pg', require: nil
  gem 'hiredis'
  gem 'rainbows',  require: nil

  group :development, :test do
    gem 'pry'
    gem 'pry-debugger'
  end
end

platform :jruby do
  gem 'jruby-openssl'
  gem 'json'
  gem 'jdbc-postgres'

  group :development do
    gem 'ruby-debug', require: nil
    gem 'sass', require: nil
  end
end

group :development do
  gem 'shotgun', require: nil
end

group :test do
  gem 'faker'
  gem 'fabrication',        require: 'fabrication'
  gem 'minitest'
  gem 'minitest-reporters', require: 'minitest/reporters'
  gem 'rack-test',          require: 'rack/test'
  gem 'webmock'
  gem 'mocha',              require: nil
  gem 'rake',               require: nil
  gem 'poltergeist'
  gem 'phantomjs',          require: 'phantomjs/poltergeist'
  gem 'capybara'
  gem 'capybara_minitest_spec'

  platform :mri do
    gem 'simplecov',        require: nil
  end
end
