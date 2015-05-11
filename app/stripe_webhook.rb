def stripe_get_site_from_event(event)
  customer_id = event['data']['object']['customer']
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

  site.where(site_where).first
end

post '/stripe_webhook' do
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
