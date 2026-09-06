# frozen_string_literal: true

def pending_site_transfer(site)
  raw = $redis_cache.get "site_transfer:#{site.id}"
  return nil unless raw

  transfer = JSON.parse raw
  return nil unless transfer['owner_id'] == site.owner.id && transfer['session_version'] == site.session_version

  transfer
end

def site_transfer_error(site, recipient)
  return 'This site cannot be transferred.' if site.is_deleted || site.is_banned || site.is_admin || site.owner.is_deleted || site.owner.is_banned
  return 'Sites with child sites cannot be transferred.' unless site.children_dataset.empty?
  if (site.values[:plan_type] && site.values[:plan_type] != 'free') ||
      site.stripe_subscription_id || site.paypal_profile_id || site.paypal_active || site.unconverted_legacy_supporter?
    return 'End this site\'s Supporter membership before transferring it.'
  end

  unless recipient && recipient.parent? && !recipient.is_deleted && !recipient.is_banned
    return 'Enter an active parent site name.'
  end
  return 'This site already belongs to that account.' if recipient.id == site.owner.id
  return 'The receiving account must be a Supporter.' unless recipient.plan_feature(:unlimited_site_creation)
  return 'The receiving account has reached its site limit.' if recipient.account_sites_dataset.count >= Site::CHILD_SITES_MAX
  return 'The receiving account does not have enough storage.' if site.space_used > recipient.remaining_space

  nil
end

def prepare_site_transfer(site)
  dont_browser_cache
  headers 'Referrer-Policy' => 'no-referrer'
  @title = 'Transfer site'
  @site = site
  @transfer = pending_site_transfer(@site) if @site

  unless @transfer && Rack::Utils.secure_compare(@transfer['token'], params[:token].to_s)
    @transfer_error = 'This transfer link is invalid or has expired.'
    halt 404, erb(:site_transfer)
  end
end

post '/settings/:username/transfer' do
  require_login
  require_ownership_for_settings

  DB.transaction do
    @site = Site.where(id: @site.id).for_update.first
    halt 403 unless @site.owned_by? parent_site

    if params[:cancel]
      $redis_cache.del "site_transfer:#{@site.id}"
      flash[:success] = 'Transfer canceled.'
    else
      recipient = Site[username: params[:recipient].to_s.strip.downcase]
      error = site_transfer_error @site, recipient
      if error
        flash[:error] = error
        redirect "/settings/#{@site.username}#transfer"
      end

      transfer = {
        owner_id: @site.owner.id,
        recipient_id: recipient.id,
        session_version: @site.session_version,
        token: SecureRandom.hex(32)
      }
      $redis_cache.set "site_transfer:#{@site.id}", transfer.to_json, ex: 24.hours.to_i
      flash[:success] = 'Share the transfer link with the receiving account.'
    end
  end

  redirect "/settings/#{@site.username}#transfer"
end

get '/site_transfer/:site_id/:token' do
  prepare_site_transfer Site[params[:site_id].to_i]

  unless signed_in?
    session[:site_transfer_return_to] = request.path
    redirect '/signin'
  end

  @recipient = Site[@transfer['recipient_id']]
  @transfer_error = if parent_site.id != @transfer['recipient_id']
    'Sign in to the receiving account to accept this transfer.'
  else
    site_transfer_error @site, @recipient
  end
  status 403 if @transfer_error
  erb :site_transfer
end

post '/site_transfer/:site_id/:token' do
  require_login

  DB.transaction do
    site = Site.where(id: params[:site_id].to_i).for_update.first
    Site.where(id: [site&.parent_site_id, parent_site.id]).order(:id).for_update.all
    prepare_site_transfer site
    @recipient = Site[parent_site.id]
    @transfer_error = if @recipient.id != @transfer['recipient_id']
      'Sign in to the receiving account to accept this transfer.'
    else
      site_transfer_error @site, @recipient
    end
    halt 403, erb(:site_transfer) if @transfer_error

    @site.set(
      parent_site_id: @recipient.id,
      email: nil,
      email_confirmed: false,
      email_confirmation_token: nil,
      api_key: nil,
      password_reset_token: nil,
      password_reset_confirmed: false,
      email_recovery_email: nil,
      email_recovery_token_digest: nil,
      email_recovery_expires_at: nil
    )
    @site[:password] = nil
    @site.save_changes validate: false
    @site.revoke_sessions!
    $redis_cache.del "site_transfer:#{@site.id}"
  end

  @site.update_redis_proxy_record
  flash[:success] = 'Site transferred to your account.'
  redirect "/settings/#{@site.username}"
end
