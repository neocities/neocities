require './app.rb'

map('/') { run Sinatra::Application }