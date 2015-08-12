get '/plan/?' do
  @title = 'Support Us'

  if parent_site && parent_site.unconverted_legacy_supporter?
    customer = Stripe::Customer.retrieve(parent_site.stripe_customer_id)
    subscription = customer.subscriptions.first

    # Subscription was deleted, add to free plan.
    if subscription.nil?
      subscription = customer.subscriptions.create plan: 'free'
    end

    parent_site.stripe_subscription_id = subscription.id
    parent_site.plan_type = subscription.plan.id
    parent_site.save_changes
  end

  erb :'plan/index'
end

def is_special_upgrade
  params[:username] && params[:plan_type] == 'special'
end

post '/plan/update' do
  require_login

  if is_special_upgrade
    require_admin
    site = Site[username: params[:username]]

    if site.nil?
      flash[:error] = 'Cannot find the requested user.'
      redirect '/admin'
    end
  end

  site ||= parent_site

  DB.transaction do
    if site.stripe_subscription_id
      customer = Stripe::Customer.retrieve site.stripe_customer_id
      subscription = customer.subscriptions.retrieve site.stripe_subscription_id
      subscription.plan = params[:plan_type]
      subscription.save

      site.update(
        plan_ended: false,
        plan_type: params[:plan_type]
      )
    else
      customer = Stripe::Customer.create(
        card: params[:stripe_token],
        description: "#{site.username} - #{site.id}",
        email: site.email,
        plan: params[:plan_type]
      )

      site.update(
        stripe_customer_id: customer.id,
        stripe_subscription_id: customer.subscriptions.first.id,
        plan_ended: false,
        plan_type: params[:plan_type]
      )
    end
  end

  if site.email
    if is_special_upgrade
      site.send_email(
        subject: "[Neocities] Your site has been upgraded to supporter!",
        body: Tilt.new('./views/templates/email/supporter_upgrade.erb', pretty: true).render(self)
      )

      redirect '/admin'
    else
      site.send_email(
        subject: "[Neocities] You've become a supporter!",
        body: Tilt.new('./views/templates/email_subscription.erb', pretty: true).render(
          self, {
            username:   site.username,
            plan_name:  Site::PLAN_FEATURES[params[:plan_type].to_sym][:name],
            plan_space: Site::PLAN_FEATURES[params[:plan_type].to_sym][:space].to_space_pretty,
            plan_bw:    Site::PLAN_FEATURES[params[:plan_type].to_sym][:bandwidth].to_space_pretty
        })
      )
    end
  end

  if is_special_upgrade
    flash[:success] = "#{site.username} has been upgraded to supporter."
    redirect '/admin'
  end

  redirect params[:plan_type] == 'free' ? '/plan' : '/plan/thanks'
end

get '/plan/thanks' do
  require_login
  erb :'plan/thanks'
end

get '/plan/thanks-paypal' do
  require_login
  erb :'plan/thanks-paypal'
end

get '/plan/alternate/?' do
  erb :'/plan/alternate'
end
