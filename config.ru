require './app.rb'
require 'sidekiq/web'

map('/') { run Sinatra::Application }

map '/sidekiq' do
  use Rack::Auth::Basic, "Protected Area" do |username, password|
    raise 'missing sidekiq auth' unless $config['sidekiq_user'] && $config['sidekiq_pass']
    username == $config['sidekiq_user'] && password == $config['sidekiq_pass']
  end

  run Sidekiq::Web
end
