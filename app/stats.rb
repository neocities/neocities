get '/stats/?' do
  expires 14400, :public, :must_revalidate if self.class.production? # 4 hours

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

  @stats[:monthly_revenue] = 0.0

  subscriptions = []
  @stats[:cancelled_subscriptions] = 0

  customers.each do |customer|
    sub = {created_at: Time.at(customer.created)}

    if customer[:subscriptions][:data].empty?
      @stats[:cancelled_subscriptions] += 1
      next
    end

    next if customer[:subscriptions][:data].first[:plan][:amount] == 0

    sub[:status] = 'active'
    plan = customer[:subscriptions][:data].first[:plan]

    sub[:amount] = (plan[:amount] / 100.0).round(2)

    if(plan[:interval] == 'year')
      sub[:amount] = (sub[:amount] / 12).round(2)
    end

    @stats[:monthly_revenue] += sub[:amount]

    subscriptions.push sub
  end

  @stats[:subscriptions] = subscriptions

  # Hotwired for now
  @stats[:expenses] = 300.0 #/mo
  @stats[:percent_until_profit] = (
    (@stats[:monthly_revenue].to_f / @stats[:expenses]) * 100
  )

  @stats[:poverty_threshold] = 11_945
  @stats[:poverty_threshold_percent] = (@stats[:monthly_revenue].to_f / ((@stats[:poverty_threshold]/12) + @stats[:expenses])) * 100

  # http://en.wikipedia.org/wiki/Poverty_threshold

  @stats[:average_developer_salary] = 93_280.00 # google "average developer salary"
  @stats[:percent_until_developer_salary] = (@stats[:monthly_revenue].to_f / ((@stats[:average_developer_salary]/12) + @stats[:expenses])) * 100

  erb :'stats'
end