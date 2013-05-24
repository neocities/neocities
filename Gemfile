source 'https://rubygems.org'

gem 'sinatra'
gem 'redis'
gem 'sequel'
gem 'slim'
gem 'bcrypt-ruby', require: 'bcrypt'
gem 'sinatra-flash', require: 'sinatra/flash'
gem 'puma', require: nil

platform :mri do
  gem 'pg'
  gem 'hiredis'
  
  group :development, :test do
    gem 'pry'
    gem 'pry-debugger'
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

  platform :mri do
    gem 'simplecov',        require: nil
  end
end
