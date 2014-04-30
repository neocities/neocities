ENV['RACK_ENV'] ||= 'development'
ENV['TZ'] = 'UTC'
DIR_ROOT = File.expand_path File.dirname(__FILE__)
Encoding.default_internal = 'UTF-8'
Encoding.default_external = 'UTF-8'

require 'yaml'
require 'json'
require 'logger'
require 'zip'

Bundler.require
Bundler.require :development if ENV['RACK_ENV'] == 'development'

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

DB = Sequel.connect $config['database'], sslmode: 'disable', max_connections: $config['database_pool']
DB.extension :pagination

Dir.glob('workers/*.rb').each {|w| require File.join(DIR_ROOT, "/#{w}") }

if defined?(Pry)
  Pry.commands.alias_command 'c', 'continue'
  Pry.commands.alias_command 's', 'step'
  Pry.commands.alias_command 'n', 'next'
  Pry.commands.alias_command 'f', 'finish'
end

Sidekiq::Logging.logger = nil unless ENV['RACK_ENV'] == 'production'

sidekiq_redis_config = {namespace: 'neocitiesworker'}
sidekiq_redis_config[:url] = $config['sidekiq_url'] if $config['sidekiq_url']

Sidekiq.configure_server do |config|
  config.redis = sidekiq_redis_config
end

Sidekiq.configure_client do |config|
  config.redis = sidekiq_redis_config
end

require File.join(DIR_ROOT, 'workers', 'thumbnail_worker.rb')
require File.join(DIR_ROOT, 'workers', 'screenshot_worker.rb')
require File.join(DIR_ROOT, 'workers', 'email_worker.rb')

Sequel.datetime_class = Time
Sequel.extension :core_extensions
Sequel.extension :migration
Sequel::Model.plugin :validation_helpers
Sequel::Model.plugin :force_encoding, 'UTF-8'
Sequel::Model.plugin :timestamps, create: :created_at, update: :updated_at
Sequel::Model.plugin :defaults_setter
Sequel.default_timezone = 'UTC'
Sequel::Migrator.apply DB, './migrations'

Stripe.api_key = $config['stripe_api_key']

Dir.glob('models/*.rb').each {|m| require File.join(DIR_ROOT, "#{m}") }
DB.loggers << Logger.new(STDOUT) if ENV['RACK_ENV'] == 'development'

if ENV['RACK_ENV'] == 'development'
  # If new, throw up a random Server for development.
  if Server.count == 0
    Server.create ip: '127.0.0.1', slots_available: 999999
  end
end

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

# Session fix for Internet Fucking Explorer https://github.com/rkh/rack-protection/issues/11
Sinatra::Application.set :protection, except: :session_hijacking

class Sinatra::Base
  alias_method :render_original, :render
  def render(engine, data, options = {}, locals = {}, &block)
    options.merge!(pretty: self.class.development?) if engine == :slim && options[:pretty].nil?
    render_original engine, data, options, locals, &block
  end
end

class Numeric
  def roundup(nearest=10)
    self % nearest == 0 ? self : self + nearest - (self % nearest)
  end

  def rounddown(nearest=10)
    self % nearest == 0 ? self : self - (self % nearest)
  end
end