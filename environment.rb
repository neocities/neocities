ENV['RACK_ENV'] ||= 'development'
ENV['TZ'] = 'UTC'
DIR_ROOT = File.expand_path File.dirname(__FILE__)
Encoding.default_internal = 'UTF-8'
Encoding.default_external = 'UTF-8'

require 'yaml'
require 'json'
require 'logger'

Bundler.require
Bundler.require :development if ENV['RACK_ENV'] == 'development'

require 'tilt/erubis'

Dir['./ext/**/*.rb'].each {|f| require f}

# :nocov:
if ENV['TRAVIS']
  $config = YAML.load_file File.join(DIR_ROOT, 'config.yml.travis')
else
  begin
    $config = YAML.load_file(File.join(DIR_ROOT, 'config.yml'))[ENV['RACK_ENV']]
  rescue Errno::ENOENT
    puts "ERROR: Please provide a config.yml file."
    exit
  end
end
# :nocov:

raise 'hash_ip_salt is required' unless $config['ip_hash_salt']

DB = Sequel.connect $config['database'], sslmode: 'disable', max_connections: $config['database_pool']
DB.extension :pagination

require 'will_paginate/sequel'

# :nocov:
=begin
if defined?(Pry)
  Pry.commands.alias_command 'c', 'continue'
  Pry.commands.alias_command 's', 'step'
  Pry.commands.alias_command 'n', 'next'
  Pry.commands.alias_command 'f', 'finish'
end
=end
# :nocov:

Sidekiq::Logging.logger = nil unless ENV['RACK_ENV'] == 'production'

sidekiq_redis_config = {namespace: 'neocitiesworker'}
sidekiq_redis_config[:url] = $config['sidekiq_url'] if $config['sidekiq_url']

# :nocov:
Sidekiq.configure_server do |config|
  config.redis = sidekiq_redis_config
end
# :nocov:

Sidekiq.configure_client do |config|
  config.logger = nil
  config.redis = sidekiq_redis_config
end

if ENV['RACK_ENV'] == 'test'
  $redis = MockRedis.new
else
  $redis = Redis.new url: $config['redis_url']
end

$redis_cache = Redis::Namespace.new :cache, redis: $redis

# :nocov:
if ENV['RACK_ENV'] == 'development'
  # Run async jobs immediately in development.
=begin
  module Sidekiq
    module Worker
      module ClassMethods
        def perform_async(*args)
          Thread.new {
            self.new.perform *args
          }
        end
      end
    end
  end
=end
end
# :nocov:

Sequel.datetime_class = Time
Sequel.extension :core_extensions
Sequel.extension :migration
Sequel::Model.plugin :validation_helpers
Sequel::Model.plugin :force_encoding, 'UTF-8'
Sequel::Model.plugin :defaults_setter
Sequel::Model.plugin :create_timestamp
Sequel.default_timezone = 'UTC'
Sequel::Migrator.apply DB, './migrations'

Stripe.api_key = $config['stripe_api_key']

Dir.glob('models/*.rb').each {|m| require File.join(DIR_ROOT, "#{m}") }
Dir.glob('workers/*.rb').each {|w| require File.join(DIR_ROOT, "/#{w}") }

DB.loggers << Logger.new(STDOUT) if ENV['RACK_ENV'] == 'development'

Mail.defaults do
  #options = { :address => "smtp.gmail.com",
  # :port => 587,
  # :domain => 'your.host.name',
  # :user_name => '<username>',
  # :password => '<password>',
  # :authentication => 'plain',
  # :enable_starttls_auto => true }

  options = {}
  delivery_method :sendmail, options
end

Sinatra::Application.set :erb, escape_html: true

require 'sass/plugin/rack'
Sinatra::Application.use Sass::Plugin::Rack

Sass::Plugin.options[:template_location] = 'sass'
Sass::Plugin.options[:css_location] = './public/css'
Sass::Plugin.options[:style] = :nested

if ENV['RACK_ENV'] != 'development'
  Sass::Plugin.options[:style] = :compressed
  # Sass::Plugin.options[:never_update] = true
  Sass::Plugin.options[:full_exception] = false
end

PayPal::Recurring.configure do |config|
  config.sandbox = false
  config.username = $config['paypal_api_username']
  config.password = $config['paypal_api_password']
  config.signature = $config['paypal_api_signature']
end

require 'csv'

$country_codes = {}

CSV.foreach("./files/country_codes.csv") do |row|
  $country_codes[row.last] = row.first
end

gandi_opts = {}
gandi_opts[:env] = :test # unless ENV['RACK_ENV'] == 'production'
$gandi = Gandi::Session.new $config['gandi_api_key'], gandi_opts
