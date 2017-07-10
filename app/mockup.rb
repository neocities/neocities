=begin
get '/mockup/home' do
  erb :'mockup/home'
end

get '/mockup/edit' do
  erb :'mockup/edit'
end

get '/mockup/profile' do
  require_login
  erb :'mockup/profile', locals: {site: current_site}
end

get '/mockup/browse' do
  erb :'mockup/browse'
end

get '/mockup/tips' do
  erb :'mockup/tips'
end

get '/mockup/welcome' do
  require_login
  erb :'mockup/welcome', locals: {site: current_site}
end

get '/mockup/stats' do
  require_login
  erb :'mockup/stats', locals: {site: current_site}
end

get '/mockup/tutorial-c1p2' do
  require_login
  erb :'mockup/tutorial-c1p2', locals: {site: current_site}
end
=end
