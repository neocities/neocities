get '/signin/?' do
  dashboard_if_signed_in
  @title = 'Sign In'
  erb :'signin'
end

post '/signin' do
  dashboard_if_signed_in

  if Site.valid_login? params[:username], params[:password]
    site = Site.get_with_identifier params[:username]

    if site.is_banned
      flash[:error] = 'Invalid login.'
      flash[:username] = params[:username]
      redirect '/signin'
    end

    session[:id] = site.id
    redirect '/'
  else
    flash[:error] = 'Invalid login.'
    flash[:username] = params[:username]
    redirect '/signin'
  end
end

get '/signin/:username' do
  require_login
  @site = Site[username: params[:username]]

  not_found if @site.nil?

  if @site.owned_by? current_site
    session[:id] = @site.id
    redirect request.referrer
  end

  flash[:error] = 'You do not have permission to switch to this site.'
  redirect request.referrer
end

get '/signout' do
  require_login
  signout
  redirect '/'
end

def signout
  session[:id] = nil
end
