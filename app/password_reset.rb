get '/password_reset' do
  @title = 'Password Reset'
  redirect '/' if signed_in?
  erb :'password_reset'
end

post '/send_password_reset' do
  if params[:email].blank?
    flash[:error] = 'You must enter a valid email address.'
    redirect '/password_reset'
  end

  sites = Site.get_recovery_sites_with_email params[:email]

  if sites.length > 0
    token = SecureRandom.uuid.gsub('-', '')+'-'+Time.now.to_i.to_s
    sites.each do |site|
      next unless site.parent?
      site.password_reset_token = token
      site.save_changes validate: false

      body = <<-EOT
Hello! This is the Penelope the Neocities cat, and I have received a password reset request for your e-mail address.

Go to this URL to reset your password: https://neocities.org/password_reset_confirm?username=#{Rack::Utils.escape(site.username)}&token=#{Rack::Utils.escape(token)}

This link will expire in 24 hours.

If you didn't request this password reset, you can ignore it. Or hide under a bed. Or take a nap. Your call.

Meow,
Penelope
    EOT

      body.strip!

      EmailWorker.perform_async({
        from: 'web@neocities.org',
        to: params[:email],
        subject: '[Neocities] Password Reset',
        body: body
      })

    end
  end

  flash[:success] = "We sent an e-mail with password reset instructions. Check your spam folder if you don't see it in your inbox."
  redirect '/'
end

get '/password_reset_confirm' do
  @title = 'Password Reset Confirm'

  if params[:token].nil? || params[:token].strip.empty?
    flash[:error] = 'Token cannot be empty.'
    redirect '/'
  end

  reset_site = Site.where(username: params[:username], password_reset_token: params[:token]).first

  if reset_site.nil?
    flash[:error] = 'Could not find a site with this username and token.'
    redirect '/'
  end

  timestamp = Time.at(reset_site.password_reset_token.split('-').last.to_i)

  if Time.now.to_i - timestamp.to_i > Site::PASSWORD_RESET_EXPIRATION_TIME
    flash[:error] = 'Token has expired.'
    redirect '/'
  end

  if reset_site.is_deleted
    unless reset_site.undelete!
      flash[:error] = "Sorry, we cannot restore this account."
      redirect '/'
    end
  end

  reset_site.password_reset_confirmed = true
  reset_site.save_changes

  session[:id] = reset_site.id

  redirect '/settings#password'
end
