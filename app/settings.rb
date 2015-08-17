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
  erb :'settings/site'
end

post '/settings/:username/delete' do
  require_login
  require_ownership_for_settings

  if params[:confirm_username] != @site.username
    flash[:error] = 'Site user name and entered user name did not match.'
    redirect "/settings/#{@site.username}#delete"
  end

  if @site.parent? && @site.stripe_customer_id
    customer = Stripe::Customer.retrieve @site.stripe_customer_id
    subscription = customer.subscriptions.retrieve @site.stripe_subscription_id
    subscription.plan = 'free'
    subscription.save
    @site.plan_type = 'free'
    @site.save_changes validate: false
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
    profile_comments_enabled: params[:site][:profile_comments_enabled]
  )
  flash[:success] = 'Profile settings changed.'
  redirect "/settings/#{@site.username}#profile"
end

post '/settings/:username/ssl' do
  require_login
  require_ownership_for_settings

  unless params[:key] && params[:cert]
    flash[:error] = 'SSL key and certificate are required.'
    redirect "/settings/#{@site.username}#custom_domain"
  end

  begin
    key = OpenSSL::PKey::RSA.new params[:key][:tempfile].read, ''
  rescue => e
    flash[:error] = 'Could not process SSL key, file may be incorrect, damaged, or passworded (you need to remove the password).'
    redirect "/settings/#{@site.username}#custom_domain"
  end

  if !key.private?
    flash[:error] = 'SSL Key file does not have private key data.'
    redirect "/settings/#{@site.username}#custom_domain"
  end

  certs_string = params[:cert][:tempfile].read

  cert_array = certs_string.lines.slice_before(/-----BEGIN CERTIFICATE-----/).to_a.collect {|a| a.join}

  if cert_array.empty?
    flash[:error] = 'Cert file does not contain any certificates.'
    redirect "/settings/#{@site.username}#custom_domain"
  end

  cert_valid_for_domain = false

  cert_array.each do |cert_string|
    begin
      cert = OpenSSL::X509::Certificate.new cert_string
    rescue => e
      flash[:error] = 'Could not process SSL certificate, file may be incorrect or damaged.'
      redirect "/settings/#{@site.username}#custom_domain"
    end

    if cert.not_after < Time.now
      flash[:error] = 'SSL Certificate has expired, please create a new one.'
      redirect "/settings/#{@site.username}#custom_domain"
    end

    cert_cn = cert.subject.to_a.select {|a| a.first == 'CN'}.flatten[1]
    cert_valid_for_domain = true if cert_cn && cert_cn.match(@site.domain)
  end

  unless cert_valid_for_domain
    flash[:error] = "Your certificate CN (common name) does not match your domain: #{@site.domain}"
    redirect "/settings/#{@site.username}#custom_domain"
  end

  # Everything else was worse.

  crtfile = Tempfile.new 'crtfile'
  crtfile.write cert_array.join
  crtfile.close

  keyfile = Tempfile.new 'keyfile'
  keyfile.write key.to_pem
  keyfile.close

  if ENV['TRAVIS'] != 'true'
    nginx_testfile = Tempfile.new 'nginx_testfile'
    nginx_testfile.write %{
      pid /tmp/throwaway.pid;
      events {}
      error_log /dev/null error;
      http {
        access_log off;
        server {
          listen 60000 ssl;
          server_name #{@site.domain} *.#{@site.domain};
          ssl_certificate #{crtfile.path};
          ssl_certificate_key #{keyfile.path};
        }
      }
    }
    nginx_testfile.close

    line = Cocaine::CommandLine.new(
      "nginx", "-t -c :path",
      expected_outcodes: [0],
      swallow_stderr: true
    )

    begin
      output = line.run path: nginx_testfile.path
    rescue Cocaine::ExitStatusError => e
      flash[:error] = "There is something wrong with your certificate, please check with your issuing CA."
      redirect "/settings/#{@site.username}#custom_domain"
    end
  end

  @site.update ssl_key: key.to_pem, ssl_cert: cert_array.join

  flash[:success] = 'Updated SSL key/certificate.'
  redirect "/settings/#{@site.username}#custom_domain"
end

post '/settings/:username/change_name' do
  require_login
  require_ownership_for_settings

  old_username = @site.username

  if params[:name] == nil || params[:name] == ''
    flash[:error] = 'Name cannot be blank.'
    redirect "/settings/#{@site.username}#username"
  end

  if old_username == params[:name]
    flash[:error] = 'You already have this name.'
    redirect "/settings/#{@site.username}#username"
  end

  old_host = @site.host
  old_file_paths = @site.file_list.collect {|f| f[:path]}

  @site.username = params[:name]

  if @site.valid?
    DB.transaction {
      @site.save_changes
      @site.move_files_from old_username
    }

    old_file_paths.each do |file_path|
      @site.purge_cache file_path
    end

    flash[:success] = "Site/user name has been changed. You will need to use this name to login, <b>don't forget it</b>."
    redirect "/settings/#{@site.username}#username"
  else
    flash[:error] = @site.errors.first.last.first
    redirect "/settings/#{old_username}#username"
  end
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

  @site.domain = params[:domain]

  if @site.valid?
    @site.save_changes
    flash[:success] = 'The domain has been successfully updated.'
    redirect "/settings/#{@site.username}#custom_domain"
  else
    flash[:error] = @site.errors.first.last.first
    redirect "/settings/#{@site.username}#custom_domain"
  end
end

post '/settings/change_password' do
  require_login

  if !Site.valid_login?(parent_site.username, params[:current_password])
    flash[:error] = 'Your provided password does not match the current one.'
    redirect "/settings#password"
  end

  parent_site.password = params[:new_password]
  parent_site.valid?

  if params[:new_password] != params[:new_password_confirm]
    parent_site.errors.add :password, 'New passwords do not match.'
  end

  if parent_site.errors.empty?
    parent_site.save_changes
    flash[:success] = 'Successfully changed password.'
    redirect "/settings#password"
  else
    flash[:error] = current_site.errors.first.last.first
    redirect '/settings#password'
  end
end

post '/settings/change_email' do
  require_login

  if params[:email] == parent_site.email
    flash[:error] = 'You are already using this email address for this account.'
    redirect '/settings#email'
  end

  parent_site.email = params[:email]
  parent_site.email_confirmation_token = SecureRandom.hex 3
  parent_site.email_confirmed = false

  if parent_site.valid?
    parent_site.save_changes
    send_confirmation_email
    flash[:success] = 'Successfully changed email. We have sent a confirmation email, please use it to confirm your email address.'
    redirect '/settings#email'
  end

  flash[:error] = parent_site.errors.first.last.first
  redirect '/settings#email'
end

post '/settings/change_email_notification' do
  require_login

  owner = current_site.owner

  owner.send_emails = params[:send_emails]
  owner.send_comment_emails = params[:send_comment_emails]
  owner.send_follow_emails = params[:send_follow_emails]
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

  customer = Stripe::Customer.retrieve current_site.stripe_customer_id

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
