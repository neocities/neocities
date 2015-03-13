post '/stripe_webhook' do
  event = JSON.parse request.body.read
  if event['type'] == 'customer.created'
    username  = event['data']['object']['description'].split(' - ').first
    email     = event['data']['object']['email']

    EmailWorker.perform_async({
      from:    'web@neocities.org',
      to:      'contact@neocities.org',
      subject: "[Neocities] New customer: #{username}",
      body:    "#{username}\n#{email}\n#{Site[username: username].uri}"
    })
  end
  'ok'
end
