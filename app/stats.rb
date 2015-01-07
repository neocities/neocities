get '/stats/?' do
  require_admin

  @stats = {
    total_sites: Site.count,
    total_unbanned_sites: Site.where(is_banned: false).count,
    total_banned_sites: Site.where(is_banned: true).count,
    total_nsfw_sites: Site.where(is_nsfw: true).count,
    total_unbanned_nsfw_sites: Site.where(is_banned: false, is_nsfw: true).count,
    total_banned_nsfw_sites: Site.where(is_banned: true, is_nsfw: true).count
  }

  # Start with the date of the first created site

  start = Site.select(:created_at).
               exclude(created_at: nil).
               order(:created_at).
               first[:created_at].to_date

  runner = start

  monthly_stats = []

  now = Date.today

  until runner.to_time > now.next_month.to_time
    monthly_stats.push(
      date: runner,
      sites_created: Site.where(created_at: runner..runner.next_month).count,
      total_from_start: Site.where(created_at: start..runner.next_month).count,
      supporters: Site.where(created_at: start..runner.next_month).exclude(stripe_customer_id: nil).count,
    )

    runner = runner.next_month
  end

  @stats[:monthly_stats] = monthly_stats

  customers = Stripe::Customer.all limit: 100000

  @stats[:total_recurring_revenue] = 0.0

  subscriptions = []
  cancelled_subscriptions = 0

  customers.each do |customer|
    sub = {created_at: Time.at(customer.created)}
    if customer[:subscriptions]
      if customer[:subscriptions][:data].empty?
        sub[:status] = 'cancelled'
      else
        sub[:status] = 'active'
        sub[:amount] = (customer[:subscriptions][:data].first[:plan][:amount] / 100.0).round(2)
        @stats[:total_recurring_revenue] += sub[:amount]
      end
    end
    subscriptions.push sub
  end

  @stats[:subscriptions] = subscriptions
  erb :'stats'
end