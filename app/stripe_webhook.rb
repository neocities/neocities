post '/stripe_webhook' do
  event = JSON.parse request.body.read
  if event['type'] == 'customer.created'
    username  = event['data']['object']['description']
    email     = event['data']['object']['email']
  end
  'ok'
end