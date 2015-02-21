# :nocov:
get '/home_mockup' do
  erb :'home_mockup'
end

get '/edit_mockup' do
  erb :'edit_mockup'
end

get '/profile_mockup' do
  require_login
  erb :'profile_mockup', locals: {site: current_site}
end

get '/browse_mockup' do
  erb :'browse_mockup'
end

get '/tips_mockup' do
  erb :'tips_mockup'
end

get '/welcome_mockup' do
  require_login
  erb :'welcome_mockup', locals: {site: current_site}
end
# :nocov: