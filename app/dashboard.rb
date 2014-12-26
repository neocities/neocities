get '/dashboard' do
  require_login
  dashboard_init
  erb :'dashboard'
end