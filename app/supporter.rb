get '/supporter/?' do
  @title = 'Become a Supporter'
  erb :'welcome'
end

post '/supporter/end' do
  require_login
  redirect '/' unless parent_site.paying_supporter?
  parent_site.end_supporter_membership!

  flash[:success] = "Your supporter membership has been cancelled. We're sorry to see you go, but thanks again for your support! Remember, you can always become a supporter again in the future."
  redirect '/supporter'
end

post '/supporter/update' do
  require_login

  plan_type = 'supporter'

  if is_special_upgrade
    require_admin
    site = Site[username: params[:username]]

    plan_type = 'special'

    if site.nil?
      flash[:error] = 'Cannot find the requested user.'
      redirect '/admin'
    end
  end

  site ||= parent_site

  DB.transaction do
    if site.stripe_customer_id
      customer = Stripe::Customer.retrieve site.stripe_customer_id
      customer.cards.each {|card| card.delete}

      if !params[:stripe_token].blank?
        customer.sources.create source: params[:stripe_token]
      end

      subscription = customer.subscriptions.create plan: plan_type

      site.plan_ended = false
      site.plan_type = plan_type
      site.stripe_subscription_id = subscription.id
      site.save_changes validate: false
    else
      customer = Stripe::Customer.create(
        source: params[:stripe_token],
        description: "#{site.username} - #{site.id}",
        email: site.email,
        plan: plan_type
      )

      site.stripe_customer_id = customer.id
      site.stripe_subscription_id = customer.subscriptions.first.id
      site.plan_ended = false
      site.plan_type = plan_type
      site.save_changes validate: false
    end
  end

  if site.email
    if is_special_upgrade
      site.send_email(
        subject: "[Neocities] Your site has been upgraded to supporter!",
        body: Tilt.new('./views/templates/email/supporter_upgrade.erb', pretty: true).render(self)
      )

      redirect '/admin'
    end

    site.send_email(
      subject: "[Neocities] You've become a supporter!",
      body: Tilt.new('./views/templates/email_subscription.erb', pretty: true).render(
        self, {
          username:   site.username,
          plan_name:  Site::PLAN_FEATURES[params[:plan_type].to_sym][:name],
          plan_space: Site::PLAN_FEATURES[params[:plan_type].to_sym][:space].pretty,
          plan_bw:    Site::PLAN_FEATURES[params[:plan_type].to_sym][:bandwidth].pretty
      })
    )
  end

  if is_special_upgrade
    flash[:success] = "#{site.username} has been upgraded to supporter."
    redirect '/admin'
  end

  redirect '/supporter/thanks'
end

get '/supporter/thanks' do
  require_login
  erb :'supporter/thanks'
end

get '/supporter/bitcoin/?' do
  erb :'supporter/bitcoin'
end

get '/supporter/paypal' do
  require_login
  redirect '/supporter' if parent_site.supporter?

  hash = paypal_recurring_authorization_hash

  if parent_site.paypal_token
    hash.merge! token: parent_site.paypal_token
  end

  ppr = PayPal::Recurring.new hash

  paypal_response = ppr.checkout

  if !paypal_response.valid?
    flash[:error] = 'There was an issue connecting to Paypal, please contact support.'
    redirect '/supporter'
  end

  redirect paypal_response.checkout_url
end

get '/supporter/paypal/return' do
  require_login

  if params[:token].nil? || params[:PayerID].nil?
    flash[:error] = 'Unknown error, could not complete the request. Please contact Neocities support.'
  end

  ppr = PayPal::Recurring.new(paypal_recurring_hash.merge(
    token:    params[:token],
    payer_id: params[:PayerID]
  ))

  paypal_response = ppr.request_payment
  unless paypal_response.approved? && paypal_response.completed?
    flash[:error] = 'Unknown error, could not complete the request. Please contact Neocities support.'
    redirect '/supporter'
  end

  ppr = PayPal::Recurring.new(paypal_recurring_authorization_hash.merge(
    frequency:   1,
    token:       params[:token],
    period:      :monthly,
    reference:   current_site.id.to_s,
    payer_id:    params[:PayerID],
    start_at:    1.month.from_now,
    failed:      3,
    outstanding: :next_billing
  ))

  paypal_response = ppr.create_recurring_profile

  current_site.paypal_token = params[:token]
  current_site.paypal_profile_id = paypal_response.profile_id
  current_site.paypal_active = true
  current_site.plan_type = 'supporter'
  current_site.plan_ended = false
  current_site.save_changes validate: false

  redirect '/supporter/thanks'
end

def paypal_recurring_hash
  {
    ipn_url:     "https://neocities.org/webhooks/paypal",
    description: 'Neocities Supporter - Monthly',
    amount:      Site::PLAN_FEATURES[:supporter][:price].to_s,
    currency:    'USD'
  }
end

def paypal_recurring_authorization_hash
  paypal_recurring_hash.merge(
    return_url:  "https://neocities.org/supporter/paypal/return",
    cancel_url:  "https://neocities.org/supporter",
    ipn_url:     "https://neocities.org/webhooks/paypal"
  )
end

def is_special_upgrade
  params[:username] && params[:plan_type] == 'special'
end
