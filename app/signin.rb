get '/signin/?' do
  dashboard_if_signed_in
  @title = 'Sign In'
  @description = 'Sign in to your Neocities account.'
  erb :'signin/index'
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

    if site.is_deleted && !site.is_banned
      session[:deleted_site_id] = site.id
      redirect '/signin/restore'
    end

    session[:id] = site.id
    redirect '/'
  else
    flash[:error] = 'Invalid login.'
    flash[:username] = params[:username]
    redirect '/signin'
  end
end

get '/signin/restore' do
  redirect '/' unless session[:deleted_site_id]
  @site = Site[session[:deleted_site_id]]
  redirect '/' if @site.nil?
  @title = 'Restore Deleted Site'
  erb :'signin/restore'
end

get '/signin/cancel_restore' do
  session[:deleted_site_id] = nil
  flash[:success] = 'Site restore was cancelled.'
  redirect '/'
end

post '/signin/restore' do
  redirect '/' unless session[:deleted_site_id]
  @site = Site[session[:deleted_site_id]]

  session[:deleted_site_id] = nil

  if @site.is_banned || !@site.undelete!
    flash[:error] = "Sorry, we cannot restore this account."
  else
    session[:id] = @site.id
  end

  redirect '/'
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

post '/signout' do
  require_login
  signout
  redirect '/'
end
