get '/plan/?' do
  @title = 'Support Us'

  if parent_site && parent_site.unconverted_legacy_supporter?
    customer = Stripe::Customer.retrieve(parent_site.stripe_customer_id)
    subscription = customer.subscriptions.first
    parent_site.stripe_subscription_id = subscription.id
    parent_site.plan_type = subscription.plan.id
    parent_site.save_changes
  end

  erb :'plan/index'
end

post '/plan/update' do
  require_login

  DB.transaction do
    if parent_site.stripe_subscription_id
      customer = Stripe::Customer.retrieve parent_site.stripe_customer_id
      subscription = customer.subscriptions.retrieve parent_site.stripe_subscription_id
      subscription.plan = params[:plan_type]
      subscription.save

      parent_site.update(
        plan_ended: false,
        plan_type: params[:plan_type]
      )
    else
      customer = Stripe::Customer.create(
        card: params[:stripe_token],
        description: "#{parent_site.username} - #{parent_site.id}",
        email: (current_site.email || parent_site.email),
        plan: params[:plan_type]
      )

      parent_site.update(
        stripe_customer_id: customer.id,
        stripe_subscription_id: customer.subscriptions.first.id,
        plan_ended: false,
        plan_type: params[:plan_type]
      )
    end
  end

  if current_site.email || parent_site.email
    EmailWorker.perform_async({
      from: 'web@neocities.org',
      reply_to: 'contact@neocities.org',
      to: current_site.email || parent_site.email,
      subject: "[Neocities] You've become a supporter!",
      body: Tilt.new('./views/templates/email_subscription.erb', pretty: true).render(self, plan_name: Site::PLAN_FEATURES[params[:plan_type].to_sym][:name], plan_space: Site::PLAN_FEATURES[params[:plan_type].to_sym][:space].to_space_pretty)
    })
  end

  redirect params[:plan_type] == 'free' ? '/plan' : '/plan/thanks'
end

get '/plan/thanks' do
  require_login
  erb :'plan/thanks'
end

get '/plan/alternate' do
  erb :'/plan/alternate'
end