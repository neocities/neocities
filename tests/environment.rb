ENV['RACK_ENV'] = 'test'
raise 'Forget it.' if ENV['RACK_ENV'] == 'production'

require 'coveralls'
require 'simplecov'

SimpleCov::Formatter::MultiFormatter[
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
]
SimpleCov.coverage_dir File.join('tests', 'coverage')
SimpleCov.start do
  add_filter "/migrations/"
end

SimpleCov.command_name 'minitest'

require 'rack_session_access'
require './environment'
require './app'

Bundler.require :test

#require 'minitest/pride'
require 'minitest/autorun'
require 'webmock'
include WebMock::API
require 'webmock/minitest'
require 'sidekiq/testing'

WebMock.disable_net_connect! allow_localhost: true

Sinatra::Application.configure do |app|
  app.use RackSessionAccess::Middleware
end

require 'capybara/poltergeist'
require 'rack_session_access/capybara'

Site.bcrypt_cost = BCrypt::Engine::MIN_COST

MiniTest::Reporters.use! MiniTest::Reporters::SpecReporter.new

# Bootstrap the database
Sequel.extension :migration

Sequel::Migrator.apply DB, './migrations', 0
Sequel::Migrator.apply DB, './migrations'

Fabrication.configure do |config|
  config.fabricator_path = 'tests/fabricators'
  config.path_prefix = DIR_ROOT
end

I18n.enforce_available_locales = true

Mail.defaults do
  delivery_method :test
end
