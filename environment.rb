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

DB = Sequel.connect $config['database'], sslmode: 'disable', max_connections: $config['database_pool']

Dir.glob('workers/*.rb').each {|w| require File.join(DIR_ROOT, "/#{w}") }

if defined?(Pry)
  Pry.commands.alias_command 'c', 'continue'
  Pry.commands.alias_command 's', 'step'
  Pry.commands.alias_command 'n', 'next'
  Pry.commands.alias_command 'f', 'finish'
end

Sidekiq.configure_server do |config|
  config.redis = { namespace: 'neocitiesworker' }
end

Sidekiq.configure_client do |config|
  config.redis = { namespace: 'neocitiesworker' }
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

class Sinatra::Base
  alias_method :render_original, :render
  def render(engine, data, options = {}, locals = {}, &block)
    options.merge!(pretty: self.class.development?) if engine == :slim && options[:pretty].nil?
    render_original engine, data, options, locals, &block
  end
end
