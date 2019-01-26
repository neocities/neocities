get '/settings/?' do
  require_login
  @site = parent_site
  erb :'settings/account'
end

def require_ownership_for_settings
  @site = Site[username: params[:username]]

  not_found if @site.nil?

  unless @site.owned_by? parent_site
    flash[:error] = 'Cannot edit this site, you do not have permission.'
    redirect request.referrer
  end
end

get '/settings/:username/?' do |username|
  # This is for the email_unsubscribe below
  pass if Site.select(:id).where(username: username).first.nil?
  require_login
  require_ownership_for_settings
  @title = "Site settings for #{username}"
  erb :'settings/site'
end

post '/settings/:username/delete' do
  require_login
  require_ownership_for_settings

  if params[:confirm_username] != @site.username
    flash[:error] = 'Site user name and entered user name did not match.'
    redirect "/settings/#{@site.username}#delete"
  end

  @site.deleted_reason = params[:deleted_reason]
  @site.save validate: false
  @site.destroy

  flash[:success] = 'Site deleted.'

  if @site.username == current_site.username
    signout
    redirect '/'
  end

  redirect '/settings#sites'
end

post '/settings/:username/profile' do
  require_login
  require_ownership_for_settings

  @site.update(
    profile_comments_enabled: params[:site][:profile_comments_enabled],
    profile_enabled: params[:site][:profile_enabled],
    ipfs_archiving_enabled: params[:site][:ipfs_archiving_enabled]
  )
  flash[:success] = 'Profile settings changed.'
  redirect "/settings/#{@site.username}#profile"
end

post '/settings/:username/change_name' do
  require_login
  require_ownership_for_settings

  old_username = @site.username

  if params[:name] == nil || params[:name] == ''
    flash[:error] = 'Name cannot be blank.'
    redirect "/settings/#{@site.username}#username"
  end

  if old_username.downcase == params[:name].downcase
    flash[:error] = 'You already have this name.'
    redirect "/settings/#{@site.username}#username"
  end

  old_host = @site.host
  old_site_file_paths = @site.site_files.collect {|site_file| site_file.path}

  @site.username = params[:name]

  if @site.valid?
    DB.transaction {
      @site.save_changes
      @site.move_files_from old_username
    }

    old_site_file_paths.each do |site_file_path|
      @site.delete_cache site_file_path
    end

    flash[:success] = "Site/user name has been changed. You will need to use this name to login, <b>don't forget it!</b>"
    redirect "/settings/#{@site.username}#username"
  else
    flash[:error] = @site.errors.first.last.first
    redirect "/settings/#{old_username}#username"
  end
end

post '/settings/:username/tipping' do
  require_login
  require_ownership_for_settings

  current_site.tipping_enabled = params[:site][:tipping_enabled]
  current_site.tipping_paypal = params[:site][:tipping_paypal]
  current_site.tipping_bitcoin = params[:site][:tipping_bitcoin]

  if current_site.valid?
    current_site.save_changes
    flash[:success] = "Tip settings have been updated."
  else
    flash[:error] = current_site.errors.first.last.first
  end

  redirect "/settings/#{current_site.username}#tipping"
end

post '/settings/:username/change_nsfw' do
  require_login
  require_ownership_for_settings

  redirect "/settings/#{@site.username}" if @site.admin_nsfw == true

  @site.is_nsfw = params[:is_nsfw]
  @site.save_changes validate: false
  flash[:success] = @site.is_nsfw ? 'Marked 18+' : 'Unmarked 18+'
  redirect "/settings/#{@site.username}#nsfw"
end

post '/settings/:username/custom_domain' do
  require_login
  require_ownership_for_settings

  original_domain = @site.domain
  @site.domain = params[:domain]

  if params[:domain] =~ /^www\..+$/i
    flash[:error] = 'Cannot begin with www - please only enter the domain name.'
    redirect "/settings/#{@site.username}/#custom_domain"
  end

  begin
    Socket.gethostbyname @site.values[:domain]
  rescue SocketError => e
    if e.message =~ /name or service not known/i
      flash[:error] = 'Domain needs to be valid and already registered.'
      redirect "/settings/#{@site.username}#custom_domain"
    elsif e.message =~ /No address associated with hostname/i
      #flash[:error] = "The domain isn't setup to use Neocities yet, cannot add. Please make the A and CNAME record changes where you registered your domain."
      #redirect "/settings/#{@site.username}#custom_domain"
    else
      raise e
    end
  end

  if @site.valid?
    @site.save_changes

    if @site.domain != original_domain
      LetsEncryptWorker.perform_async @site.id
      # Sometimes the www record isn't ready for some reason, so try a delay to fix that.
      LetsEncryptWorker.perform_in 40.minutes, @site.id
    end

    flash[:success] = 'The domain has been successfully updated! Make sure your configuration with the domain registrar is correct. It could take a while for the changes to take effect (15-40 minutes), please be patient.'
    redirect "/settings/#{@site.username}#custom_domain"
  else
    flash[:error] = @site.errors.first.last.first
    redirect "/settings/#{@site.username}#custom_domain"
  end
end

post '/settings/:username/generate_api_key' do
  require_login
  require_ownership_for_settings
  is_new = current_site.api_key.nil?
  current_site.generate_api_key!

  msg = is_new ? "New API key has been generated." : "API key has been regenerated."
  flash[:success] = msg
  redirect "/settings/#{current_site.username}#api_key"
end

post '/settings/change_password' do
  require_login

  if !current_site.password_reset_confirmed && !Site.valid_login?(parent_site.username, params[:current_password])
    flash[:error] = 'Your provided password does not match the current one.'
    redirect "/settings#password"
  end

  parent_site.password = params[:new_password]
  parent_site.valid?

  if params[:new_password] != params[:new_password_confirm]
    parent_site.errors.add :password, 'New passwords do not match.'
  end

  parent_site.password_reset_token = nil
  parent_site.password_reset_confirmed = false

  if parent_site.errors.empty?
    parent_site.save_changes

    parent_site.send_email(
      subject: "[Neocities] Your password has been changed",
      body: Tilt.new('./views/templates/email/password_changed.erb', pretty: true).render(self)
    )

    flash[:success] = 'Successfully changed password.'
    redirect "/settings#password"
  else
    flash[:error] = current_site.errors.first.last.first
    redirect '/settings#password'
  end
end

post '/settings/change_email' do
  require_login

  if params[:from_confirm]
    redirect_url = "/site/#{parent_site.username}/confirm_email"
  else
    redirect_url = '/settings#email'
  end

  if params[:email] == parent_site.email
    flash[:error] = 'You are already using this email address for this account.'
    redirect redirect_url
  end

  previous_email = parent_site.email
  parent_site.email = params[:email]
  parent_site.email_confirmation_token = SecureRandom.hex 3
  parent_site.email_confirmed = false
  parent_site.password_reset_token = nil

  if parent_site.valid?
    parent_site.save_changes
    send_confirmation_email

    parent_site.send_email(
      subject: "[Neocities] Your email address has been changed",
      body: Tilt.new('./views/templates/email/email_changed.erb', pretty: true).render(self, site: parent_site, previous_email: previous_email)
    )

    if !parent_site.supporter?
      session[:fromsettings] = true
      redirect "/site/#{parent_site.email}/confirm_email"
    else
      flash[:success] = 'Email address changed.'
      redirect '/settings#email'
    end
  end

  flash[:error] = parent_site.errors.first.last.first
  redirect redirect_url
end

post '/settings/change_email_notification' do
  require_login

  owner = current_site.owner

  owner.send_emails = params[:send_emails]
  owner.send_comment_emails = params[:send_comment_emails]
  owner.send_follow_emails = params[:send_follow_emails]
  owner.email_invoice = params[:email_invoice]
  owner.save_changes validate: false
  flash[:success] = 'Email notification settings have been updated.'
  redirect '/settings#email'
end

post '/settings/create_child' do
  require_login

  if !current_site.plan_feature(:unlimited_site_creation)
    flash[:error] = 'Cannot create a new site with your current plan, please become a supporter.'
    redirect '/settings#sites'
  end

  site = Site.new

  site.parent_site_id = parent_site.id
  site.username = params[:username]

  if site.valid?
    site.save
    flash[:success] = 'Your new site has been created! To manage it, click your username in the top right and go to "Switch Site".'
    redirect '/settings#sites'
  else
    flash[:error] = site.errors.first.last.first
    redirect '/settings#sites'
  end
end

get '/settings/unsubscribe_email/?' do
  redirect "/settings/#email" if signed_in?

  if params[:email] && params[:token] && params[:email] != '' && Site.valid_email_unsubscribe_token?(params[:email], params[:token])
    Site.where(email: params[:email]).all.each do |site|
      site.send_emails = false
      site.save_changes validate: false
    end

    @message = "You have been successfully unsubscribed from future emails to #{params[:email]}. Our apologies for the inconvenience."
  else
    @message = 'There was an error unsubscribing your email address. Please contact support.'
  end
  erb :'settings/account/unsubscribe'
end

post '/settings/update_card' do
  require_login

  customer = Stripe::Customer.retrieve parent_site.stripe_customer_id

  old_card_ids = customer.sources.collect {|s| s.id}

  begin
    customer.sources.create source: params[:stripe_token]
  rescue Stripe::InvalidRequestError => e
    if  e.message.match /cannot use a.+token more than once/
      flash[:error] = 'Card is already being used.'
      redirect '/settings#billing'
    else
      raise e
    end
  end

  old_card_ids.each do |card_id|
    customer.sources.retrieve(card_id).delete
  end

  flash[:success] = 'Card information updated.'
  redirect '/settings#billing'
end
