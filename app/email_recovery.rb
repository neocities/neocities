# frozen_string_literal: true

def site_for_email_recovery(token)
  return nil if token.to_s.empty?

  site = Site[email_recovery_token_digest: email_login_digest(token.to_s)]
  return nil if site.nil? || !site.parent? || site.is_banned
  return nil if site.email_recovery_expires_at.nil? || site.email_recovery_expires_at <= Time.now

  site
end

def prepare_email_recovery_page
  dont_browser_cache
  headers 'Referrer-Policy' => 'no-referrer'
end

get '/email_recovery/:token' do
  prepare_email_recovery_page
  @site = site_for_email_recovery params[:token]

  unless @site
    flash[:error] = 'This email recovery link is invalid or has expired.'
    redirect '/signin'
  end

  @token = params[:token]
  @title = 'Recover Account Email'
  erb :'email_recovery'
end

post '/email_recovery/:token' do
  prepare_email_recovery_page
  @site = site_for_email_recovery params[:token]

  unless @site
    flash[:error] = 'This email recovery link is invalid or has expired.'
    redirect '/signin'
  end

  if non_signin_password_auth_rate_limited?(@site.username, request.ip)
    flash[:error] = 'Too many recovery attempts. Please try again later.'
    redirect "/email_recovery/#{params[:token]}"
  end

  old_email_matches = Rack::Utils.secure_compare(
    @site.email.to_s.downcase,
    params[:old_email].to_s.strip.downcase
  )
  password_matches = @site.valid_password? params[:password].to_s

  unless old_email_matches && password_matches
    record_failed_non_signin_password_auth @site.username, request.ip
    flash[:error] = 'The current email address or password was incorrect.'
    redirect "/email_recovery/#{params[:token]}"
  end

  token_digest = email_login_digest params[:token].to_s
  old_email = nil
  recovered_site = nil
  recovery_error = nil

  DB.transaction do
    recovered_site = Site.where(id: @site.id).for_update.first

    if recovered_site.nil? || recovered_site.is_banned ||
        recovered_site.email_recovery_token_digest != token_digest ||
        recovered_site.email_recovery_expires_at.nil? ||
        recovered_site.email_recovery_expires_at <= Time.now ||
        recovered_site.email.to_s.downcase != params[:old_email].to_s.strip.downcase ||
        !recovered_site.valid_password?(params[:password].to_s)
      recovery_error = 'This email recovery link is invalid or has expired.'
      raise Sequel::Rollback
    end

    old_email = recovered_site.email
    recovered_site.email = recovered_site.email_recovery_email
    recovered_site.email_confirmed = true
    recovered_site.email_confirmation_token = nil
    recovered_site.email_confirmation_count = 0
    recovered_site.email_reviewed_at = Time.now
    recovered_site.password_reset_token = nil
    recovered_site.password_reset_confirmed = false
    recovered_site.email_recovery_email = nil
    recovered_site.email_recovery_token_digest = nil
    recovered_site.email_recovery_expires_at = nil

    unless recovered_site.valid?
      recovery_error = recovered_site.errors[:email]&.first || recovered_site.errors.first.last.first
      raise Sequel::Rollback
    end

    recovered_site.save_changes
  end

  if recovery_error
    flash[:error] = recovery_error
    redirect "/email_recovery/#{params[:token]}"
  end

  clear_failed_non_signin_password_auth recovered_site.username
  invalidate_email_login_challenges recovered_site
  clear_pending_email_login

  EmailWorker.perform_async({
    from: Site::FROM_EMAIL,
    to: old_email,
    subject: '[Neocities] Your email address has been changed',
    body: Tilt.new('./views/templates/email/email_recovery_changed.erb', pretty: true).render(self),
    no_footer: true
  })

  flash[:success] = 'Your email address has been changed. Please sign in using your new email.'
  redirect '/signin'
end
