post '/webhooks/paypal' do
  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'errors@neocities.org',
    subject: "[Neocities Paypal Webhook] Received a Webhook from Paypal",
    body: params.inspect,
    no_footer: true
  })

  'ok'
end

def valid_paypal_webhook_source?
  # https://www.paypal-knowledge.com/infocenter/index?page=content&widgetview=true&id=FAQ1465&viewlocale=en_US&direct=en
  return true if ['127.0.0.1', '173.0.81.1', '173.0.81.33', '66.211.170.66'].include?(request.ip)
  false
end

post '/webhooks/paypal/tipping_notify' do
  return 403 unless valid_paypal_webhook_source?
  payload = JSON.parse Base64.strict_decode64(params[:custom]), symbolize_names: true

  site = Site[payload[:site_id]]

  @tip_hash = {
    message: (params[:memo] ? params[:memo] : nil),
    amount: params[:mc_gross],
    currency: params[:mc_currency],
    fee: params[:mc_fee],
    actioning_site: (payload[:actioning_site_id] ? Site[payload[:actioning_site_id]] : nil),
    paypal_payer_email: params[:payer_email],
    paypal_receiver_email: params[:receiver_email],
    paypal_txn_id: params[:txn_id],
    created_at: DateTime.strptime(params[:payment_date], "%H:%M:%S %b %e, %Y %Z").to_time
  }

  @tip = site.add_tip @tip_hash

  Event.create(
    site_id: @tip.site.id,
    actioning_site_id: (@tip.actioning_site ? @tip.actioning_site.id : nil),
    tip_id: @tip.id
  )

  if @tip.actioning_site
    subject = "You received a #{@tip.amount_string} tip from #{@tip.actioning_site.username}!"
  else
    subject = "You received a #{@tip.amount_string} tip!"
  end

  @tip.site.send_email(
    subject: subject,
    body: Tilt.new('./views/templates/email/tip_received.erb', pretty: true).render(self)
  )

  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: params[:payer_email],
    subject: "You sent a #{@tip.amount_string} tip!",
    body: Tilt.new('./views/templates/email/tip_sent.erb', pretty: true).render(self)
  })
end

post '/webhooks/stripe' do
  event = JSON.parse request.body.read
  if event['type'] == 'customer.created'
    username  = event['data']['object']['description'].split(' - ').first
    email     = event['data']['object']['email']

    EmailWorker.perform_async({
      from:    'web@neocities.org',
      to:      'contact@neocities.org',
      subject: "[Neocities] New customer: #{username}",
      body:    "#{username}\n#{email}\n#{Site[username: username].uri}",
      no_footer: true
    })
  end

  if event['type'] == 'charge.failed'
    site = stripe_get_site_from_event event

    EmailWorker.perform_async({
      from:    'web@neocities.org',
      to:      site.email,
      subject: "[Neocities] There was an issue charging your card",
      body:    Tilt.new('./views/templates/email/charge_failure.erb', pretty: true).render(self)
    })
  end

  if event['type'] == 'customer.subscription.deleted'
    site = stripe_get_site_from_event event
    site.stripe_subscription_id = nil
    site.plan_type = nil
    site.plan_ended = true
    site.save_changes validate: false

    EmailWorker.perform_async({
      from:    'web@neocities.org',
      to:      site.email,
      subject: "[Neocities] Supporter plan has ended",
      body:    Tilt.new('./views/templates/email/supporter_ended.erb', pretty: true).render(self)
    })
  end

  'ok'
end

def stripe_get_site_from_event(event)
  customer_id = event['data']['object']['customer']
  return 'ok' if customer_id.nil? # Likely a fraudulent card report
  customer = Stripe::Customer.retrieve customer_id

  # Some old accounts only have a username for the desc
  desc_split = customer.description.split(' - ')

  if desc_split.length == 1
    site_where = {username: desc_split.first}
  end

  if desc_split.last.to_i == 0
    site_where = {username: desc_split.first}
  else
    site_where = {id: desc_split.last}
  end

  Site.where(site_where).first
end
