get '/?' do
  if current_site
    require_login

    @suggestions = current_site.suggestions

    @current_page = params[:current_page].to_i
    @current_page = 1 if @current_page == 0

    if params[:activity] == 'mine'
      events_dataset = current_site.latest_events(@current_page, 10)
    elsif params[:event_id]
      event = Event.select(:id).where(id: params[:event_id]).first
      not_found if event.nil?
      events_dataset = Event.where(id: params[:event_id]).paginate(1, 1)
    else
      events_dataset = current_site.news_feed(@current_page, 10)
    end

    @page_count = events_dataset.page_count || 1
    @events = events_dataset.all

    current_site.events_dataset.update notification_seen: true

    halt erb :'home', locals: {site: current_site}
  end

  if SimpleCache.expired?(:sites_count)
    @sites_count = SimpleCache.store :sites_count, Site.count.roundup(100), 600 # 10 Minutes
  else
    @sites_count = SimpleCache.get :sites_count
  end

  erb :index, layout: false
end

get '/welcome' do
  require_login
  redirect '/' if current_site.plan_type != 'free'
  erb :'welcome'
end

get '/tutorials' do
  erb :'tutorials'
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