ENV['RACK_ENV'] = 'test'
raise 'Forget it.' if ENV['RACK_ENV'] == 'production'

require 'simplecov'
SimpleCov.coverage_dir File.join('tests', 'coverage')
SimpleCov.start do
  add_filter "/migrations/"
end

SimpleCov.command_name 'minitest'

require './environment'
require 'webmock'
include WebMock::API
require './app'

Bundler.require :test

#require 'minitest/pride'
require 'minitest/autorun'
require 'sidekiq/testing/inline'

Account.bcrypt_cost = BCrypt::Engine::MIN_COST

MiniTest::Reporters.use! MiniTest::Reporters::SpecReporter.new

# Bootstrap the database
Sequel.extension :migration

Sequel::Migrator.apply DB, './migrations', 0
Sequel::Migrator.apply DB, './migrations'

Fabrication.configure do |config|
  config.fabricator_path = 'tests/fabricators'
  config.path_prefix = DIR_ROOT
end