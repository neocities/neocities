get '/?' do
  if current_site
    require_login

    redirect '/dashboard' if current_site.is_education

    @page = params[:page]
    @page = 1 if @page.not_an_integer?

    if params[:activity] == 'mine'
      events_dataset = current_site.latest_events(@page, 10)
    elsif params[:event_id]
      event = Event.select(:id).where(id: params[:event_id]).first
      not_found if event.nil?
      not_found if event.is_deleted
      events_dataset = Event.where(id: params[:event_id]).paginate(1, 1)
    elsif params[:activity] == 'global'
      events_dataset = Event.global_dataset @page
    else
      events_dataset = current_site.news_feed(@page, 10)
    end

    @pagination_dataset = events_dataset
    @events = events_dataset.all

    current_site.events_dataset.update notification_seen: true

    halt erb :'home', locals: {site: current_site}
  end

  if SimpleCache.expired?(:index)
    @sites_count = Site.count.roundup(100)
    @total_hits_count = DB['SELECT SUM(hits) AS hits FROM SITES'].first[:hits] || 0
    @total_views_count = DB['SELECT SUM(views) AS views FROM SITES'].first[:views] || 0
    @changed_count = DB['SELECT SUM(changed_count) AS changed_count FROM SITES'].first[:changed_count] || 0
    @blog_feed_html = ''

    begin
      xml = HTTP.timeout(global: 2).get('https://blog.neocities.org/feed.xml').to_s
      feed = Feedjira::Feed.parse xml
      feed.entries[0..2].each do |entry|
        @blog_feed_html += %{<a href="#{entry.url}">#{entry.title.split('.').first}</a> <span style="float: right">#{entry.published.strftime('%b %-d, %Y')}</span><br>}
      end
    rescue
      @blog_feed_html = 'The latest news on Neocities can be found on our blog.'
    end

    @create_disabled = false

    @index_rendered = SimpleCache.store :index, erb(:index, layout: :index_layout), (ENV['RACK_ENV'] == 'test' ? -1 : 1.hour)

    return @index_rendered
  else
    return SimpleCache.get(:index)
  end
end

get '/welcome' do
  require_login
  redirect '/' if current_site.supporter?
  @title = 'Welcome!'
  erb :'welcome', locals: {site: current_site}
end

get '/education' do
  redirect '/' if signed_in?
  erb :education, layout: :index_layout
end

get '/donate' do
  erb :'donate'
end

get '/about' do
  erb :'about'
end

get '/terms' do
  erb :'terms'
end

get '/privacy' do
  erb :'privacy'
end

get '/press' do
  erb :'press'
end

get '/legal/?' do
  @title = 'Legal Guide to Neocities'
  erb :'legal'
end

get '/thankyou' do
  @title = 'Thank you!'
  erb :'thankyou'
end

get '/cli' do
  @title = 'Command Line Interface'
  erb :'cli'
end

get '/forgot_username' do
  @title = 'Forgot Username'
  erb :'forgot_username'
end

post '/forgot_username' do
  if params[:email].blank?
    flash[:error] = 'Cannot use an empty email address!'
    redirect '/forgot_username'
  end

  sites = Site.get_recovery_sites_with_email params[:email]

  sites.each do |site|
    body = <<-EOT
Hello! This is the Neocities cat, and I have received a username lookup request using this email address.

Your username is #{site.username}

If you didn't request this, you can ignore it. Or hide under a bed. Or take a nap. Your call.

Meow,
the Neocities Cat
    EOT

    body.strip!

    EmailWorker.perform_async({
      from: 'web@neocities.org',
      to: params[:email],
      subject: '[Neocities] Username lookup',
      body: body
    })

  end

  flash[:success] = 'If your email was valid, the Neocities Cat will send an e-mail with your username in it.'
  redirect '/'
end
