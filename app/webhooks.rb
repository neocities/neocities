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
    site_id = event['data']['object']['description'].split(' - ').last
    site = Site[site_id]

    EmailWorker.perform_async({
      from:    'web@neocities.org',
      to:      site.email,
      subject: "[Neocities] There was an issue charging your card",
      body:    Tilt.new('./views/templates/email/charge_failure.erb', pretty: true).render(self)
    })
  end

  if event['type'] == 'customer.subscription.deleted'
    site_id = event['data']['object']['description'].split(' - ').last
    site = Site[site_id]
    site.stripe_subscription_id = nil
    site.plan_type = nil
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
