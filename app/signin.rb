get '/signin/?' do
  dashboard_if_signed_in
  @title = 'Sign In'
  @description = 'Sign in to your Neocities account.'
  @captcha_required = signin_captcha_required?
  erb :'signin/index'
end

post '/signin' do
  dashboard_if_signed_in

  if signin_captcha_required? && !signin_captcha_valid?
    flash[:error] = 'Please complete the captcha.'
    flash[:username] = params[:username]
    redirect '/signin'
  end

  site = Site.get_site_from_login(params[:username], params[:password])

  if site && !site.is_banned
    session.delete :signin_attempts

    if site.is_deleted && !site.is_banned
      session[:deleted_site_id] = site.id
      redirect '/signin/restore'
    end

    unless begin_email_login site, request.ip
      flash[:error] = 'Please wait before requesting another sign in verification code.'
      flash[:username] = params[:username]
      redirect '/signin'
    end

    redirect '/signin/verify'
  else
    record_failed_signin_attempt
    flash[:error] = 'Invalid login.'
    flash[:username] = params[:username]
    redirect '/signin'
  end
end

get '/signin/verify' do
  dashboard_if_signed_in
  challenge = pending_email_login
  @site = challenge[:site] if challenge

  unless @site
    clear_pending_email_login
    flash[:error] = 'Your sign in verification code has expired. Please sign in again.'
    redirect '/signin'
  end

  dont_browser_cache
  @masked_email = masked_email @site.owner.email
  @title = 'Verify Sign In'
  erb :'signin/verify'
end

post '/signin/verify' do
  dashboard_if_signed_in
  challenge = pending_email_login

  unless challenge
    clear_pending_email_login
    flash[:error] = 'Your sign in verification code has expired. Please sign in again.'
    redirect '/signin'
  end

  code = params[:code].to_s.strip
  expected_digest = challenge[:code_digest].to_s
  valid_code = code.match?(/\A\d{6}\z/) &&
    Rack::Utils.secure_compare(email_login_digest(code), expected_digest)

  if valid_code
    unless consume_email_login_challenge challenge
      clear_pending_email_login
      flash[:error] = 'Your sign in verification code has expired. Please sign in again.'
      redirect '/signin'
    end

    site = challenge[:site]
    if challenge[:action] == 'restore' && site.is_deleted && !site.undelete!
      flash[:error] = 'Sorry, we cannot restore this account.'
      redirect '/'
    end

    session[:id] = site.id
    redirect '/'
  end

  attempts = record_failed_email_login_attempt challenge
  if attempts >= EMAIL_LOGIN_MAX_ATTEMPTS
    flash[:error] = 'Too many incorrect verification codes. Please sign in again.'
    redirect '/signin'
  end

  flash[:error] = 'Invalid verification code.'
  redirect '/signin/verify'
end

post '/signin/cancel' do
  dashboard_if_signed_in
  clear_pending_email_login
  redirect '/signin'
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

  if @site.nil? || @site.is_banned
    flash[:error] = "Sorry, we cannot restore this account."
    redirect '/'
  end

  unless begin_email_login @site, request.ip, action: 'restore'
    flash[:error] = 'Please wait before requesting another sign in verification code.'
    redirect '/signin'
  end

  redirect '/signin/verify'
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
