ENV['RACK_ENV'] ||= 'development'
ENV['TZ'] = 'UTC'
DIR_ROOT = File.expand_path File.dirname(__FILE__)
Encoding.default_internal = 'UTF-8'
Encoding.default_external = 'UTF-8'

require 'yaml'
require 'json'
require 'logger'
require 'zip/zip'

Bundler.require
Bundler.require :development if ENV['RACK_ENV'] == 'development'

$config = YAML.load_file(File.join(DIR_ROOT, 'config.yml'))[ENV['RACK_ENV']]

DB = Sequel.connect $config['database'], sslmode: 'disable'

Dir.glob('workers/*.rb').each {|w| require File.join(DIR_ROOT, "/#{w}") }

if defined?(Pry)
  Pry.commands.alias_command 'c', 'continue'
  Pry.commands.alias_command 's', 'step'
  Pry.commands.alias_command 'n', 'next'
  Pry.commands.alias_command 'f', 'finish'
end

require File.join(DIR_ROOT, 'jobs', 'screenshot_job.rb')

Sequel.datetime_class = Time
Sequel.extension :pagination
Sequel.extension :migration
Sequel::Model.plugin :validation_helpers
Sequel::Model.plugin :force_encoding, 'UTF-8'
Sequel::Model.plugin :timestamps, create: :created_at, update: :updated_at
Sequel::Model.plugin :defaults_setter
Sequel.default_timezone = 'UTC'
Sequel::Migrator.apply DB, './migrations'

Dir.glob('models/*.rb').each {|m| require File.join(DIR_ROOT, "#{m}") }
DB.loggers << Logger.new(STDOUT) if ENV['RACK_ENV'] == 'development'

# If new, throw up a random Server for development.

if ENV['RACK_ENV'] == 'development' && Server.count == 0
  Server.create ip: '127.0.0.1', slots_available: 999999
end

Backburner.configure do |config|
  config.max_job_retries = 3
  config.retry_delay = 200
  config.respond_timeout = 120
end
