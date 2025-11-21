# frozen_string_literal: true
RubyVM::YJIT.enable
ENV['RACK_ENV'] ||= 'development'
ENV['TZ'] = 'UTC'
DIR_ROOT = File.expand_path File.dirname(__FILE__)
Encoding.default_internal = 'UTF-8'
Encoding.default_external = 'UTF-8'

require 'yaml'
require 'json'

Bundler.require
Bundler.require :development if ENV['RACK_ENV'] == 'development'

require 'logger'

require 'tilt/erubi'
require 'active_support'
require 'active_support/time'

ActiveSupport.to_time_preserves_timezone = :zone

class File
  def self.exists?(val)
    self.exist?(val)
  end
end

Dir['./ext/**/*.rb'].each {|f| require f}

# :nocov:
if ENV['CI']
  $config = YAML.load_file File.join(DIR_ROOT, 'config.yml.ci')
else
  begin
    $config = YAML.load_file(File.join(DIR_ROOT, 'config.yml'))[ENV['RACK_ENV']]
  rescue Errno::ENOENT
    puts "ERROR: Please provide a config.yml file."
    exit
  end
end
# :nocov:

DB = Sequel.connect $config['database'], sslmode: 'disable', max_connections: $config['database_pool']
DB.extension :pagination
DB.extension :auto_literal_strings
Sequel.split_symbols = true
Sidekiq.strict_args!(false)

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

unless ENV['RACK_ENV'] == 'production'
  Sidekiq.configure_server do |config|
    config.logger = nil
  end
end

sidekiq_redis_config = {}
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
  $redis = Redis.new(
    url: $config['redis_url'],
    read_timeout: 5.0,
    write_timeout: 5.0,
    connect_timeout: 5.0
  )
end

$redis_cache = Redis::Namespace.new :cache, redis: $redis

if ENV['RACK_ENV'] == 'test'
  $redis_proxy = MockRedis.new
else
  $redis_proxy = Redis.new(
    url: $config['redis_proxy'],
    read_timeout: 5.0,
    write_timeout: 5.0,
    connect_timeout: 5.0
  )
end

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
Sequel.default_timezone = :utc
Sequel::Migrator.apply DB, './migrations'

Stripe.api_key = $config['stripe_api_key']

Dir.glob('models/*.rb').each {|m| require File.join(DIR_ROOT, "#{m}") }
Dir.glob('workers/*.rb').each {|w| require File.join(DIR_ROOT, "/#{w}") }

DB.loggers << Logger.new(STDOUT) if ENV['RACK_ENV'] == 'development'

Mail.defaults do
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

$image_optim = ImageOptim.new pngout: false, svgo: false

Money.locale_backend = nil
Money.default_currency = Money::Currency.new("USD")
Money.rounding_mode = BigDecimal::ROUND_HALF_UP

$twilio = Twilio::REST::Client.new $config['twilio_account_sid'], $config['twilio_auth_token']

Minfraud.configure do |c|
  c.account_id  = $config['minfraud_account_id']
  c.license_key = $config['minfraud_license_key']
  c.enable_validation = true
end


Airbrake.configure do |c|
  c.project_id = $config['airbrake_project_id']
  c.project_key = $config['airbrake_project_key']
end

Airbrake.add_filter do |notice|
  if notice[:params][:password]
    # Filter out password.
    notice[:params][:password] = '[Filtered]'
  end

  notice.ignore! if notice.stash[:exception].is_a?(Sinatra::NotFound)
end

Airbrake.add_filter Airbrake::Sidekiq::RetryableJobsFilter.new
