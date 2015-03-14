get '/password_reset' do
  erb :'password_reset'
end

post '/send_password_reset' do
  sites = Site.filter(email: params[:email]).all

  if sites.length > 0
    token = SecureRandom.uuid.gsub('-', '')
    sites.each do |site|
      site.update password_reset_token: token
    end

    body = <<-EOT
Hello! This is the Neocities cat, and I have received a password reset request for your e-mail address. Purrrr.

Go to this URL to reset your password: http://neocities.org/password_reset_confirm?token=#{token}

After clicking on this link, your password for all the sites registered to this email address will be changed to this token.

Token: #{token}

If you didn't request this reset, you can ignore it. Or hide under a bed. Or take a nap. Your call.

Meow,
the Neocities Cat
    EOT

    body.strip!

    EmailWorker.perform_async({
      from: 'web@neocities.org',
      to: params[:email],
      subject: '[Neocities] Password Reset',
      body: body
    })
  end

  flash[:success] = 'If your email was valid (and used by a site), the Neocities Cat will send an e-mail to your account with password reset instructions.'
  redirect '/'
end

get '/password_reset_confirm' do
  if params[:token].nil? || params[:token].strip.empty?
    flash[:error] = 'Could not find a site with this token.'
    redirect '/'
  end

  reset_site = Site[password_reset_token: params[:token]]

  if reset_site.nil?
    flash[:error] = 'Could not find a site with this token.'
    redirect '/'
  end

  sites = Site.filter(email: reset_site.email).all

  if sites.length > 0
    sites.each do |site|
      site.password = reset_site.password_reset_token
      site.save_changes
    end

    flash[:success] = 'Your password for all sites with your email address has been changed to the token sent in your e-mail. Please login and change your password as soon as possible.'
  else
    flash[:error] = 'Could not find a site with this token.'
  end

  redirect '/'
end
