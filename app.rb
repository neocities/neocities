require 'base64'
require './environment.rb'
require './app_helpers.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       $config['session_secret']

use Rack::Recaptcha, public_key: $config['recaptcha_public_key'], private_key: $config['recaptcha_private_key']
helpers Rack::Recaptcha::Helpers

helpers do
  def site_change_file_display_class(filename)
    return 'html' if filename.match(Site::HTML_REGEX)
    return 'image' if filename.match(Site::IMAGE_REGEX)
    'misc'
  end

  def csrf_token_input_html
    %{<input name="csrf_token" type="hidden" value="#{csrf_token}">}
  end
end

before do
  if request.path.match /^\/api\//i
    @api = true
    content_type :json
  elsif request.path.match /^\/stripe_webhook$/
    # Skips the CSRF check for stripe web hooks
  else
    content_type :html, 'charset' => 'utf-8'
    redirect '/' if request.post? && !csrf_safe?
  end
end

not_found do
  erb :'not_found'
end

error do
  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'errors@neocities.org',
    subject: "[Neocities Error] #{env['sinatra.error'].class}: #{env['sinatra.error'].message}",
    body: "#{request.request_method} #{request.path}\n\n" +
          (current_site ? "Site: #{current_site.username}\nEmail: #{current_site.email}\n\n" : '') +
          env['sinatra.error'].backtrace.join("\n")
  })

  if @api
    api_error 500, 'server_error', 'there has been an unknown server error, please try again later'
  end

  erb :'error'
end

# :nocov:
get '/home_mockup' do
  erb :'home_mockup'
end

get '/edit_mockup' do
  erb :'edit_mockup'
end

get '/profile_mockup' do
  require_login
  erb :'profile_mockup', locals: {site: current_site}
end

get '/browse_mockup' do
  erb :'browse_mockup'
end

get '/tips_mockup' do
  erb :'tips_mockup'
end
# :nocov:

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

  @blackbox_question = BlackBox.generate
  @question_first_number, @question_last_number = generate_question

  erb :index, layout: false
end

def browse_sites_dataset
  @current_page = params[:current_page]
  @current_page = @current_page.to_i
  @current_page = 1 if @current_page == 0

  site_dataset = Site.filter(is_banned: false, is_crashing: false).filter(site_changed: true)

  if current_site
    if !current_site.blocking_site_ids.empty?
      site_dataset.where!(Sequel.~(Sequel.qualify(:sites, :id) => current_site.blocking_site_ids))
    end

    if current_site.blocks_dataset.count
      site_dataset.where!(
        Sequel.~(Sequel.qualify(:sites, :id) => current_site.blocks_dataset.select(:actioning_site_id).all.collect {|s| s.actioning_site_id})
      )
    end
  end

  case params[:sort_by]
    when 'hits'
      site_dataset.order!(:hits.desc, :site_updated_at.desc)
    when 'views'
      site_dataset.order!(:views.desc, :site_updated_at.desc)
    when 'newest'
      site_dataset.order!(:created_at.desc, :views.desc)
    when 'oldest'
      site_dataset.order!(:created_at, :views.desc)
    when 'random'
      site_dataset.where! 'random() < 0.01'
    when 'last_updated'
      params[:sort_by] = 'last_updated'
      site_dataset.order!(:site_updated_at.desc, :views.desc)
    else
      if params[:tag]
        params[:sort_by] = 'views'
        site_dataset.order!(:views.desc, :site_updated_at.desc)
      else
        params[:sort_by] = 'last_updated'
        site_dataset.order!(:site_updated_at.desc, :views.desc)
      end
  end

  site_dataset.where! ['sites.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]

  if params[:tag]
    site_dataset = site_dataset.association_join(:tags).select_all(:sites)
    site_dataset.where! ['tags.name = ?', params[:tag]]
    site_dataset.where! ['tags.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]
  end

  site_dataset
end

get '/browse/?' do
  params.delete 'tag' if params[:tag].nil? || params[:tag].empty?
  site_dataset = browse_sites_dataset
  site_dataset = site_dataset.paginate @current_page, Site::BROWSE_PAGINATION_LENGTH
  @page_count = site_dataset.page_count || 1
  @sites = site_dataset.all
  erb :browse
end

get '/surf/?' do
  params.delete 'tag' if params[:tag].nil? || params[:tag].empty?
  site_dataset = browse_sites_dataset
  site_dataset = site_dataset.paginate @current_page, 1
  @page_count = site_dataset.page_count || 1
  @site = site_dataset.first
  redirect "/browse?#{Rack::Utils.build_query params}" if @site.nil?
  erb :'surf', layout: false
end

get '/surf/:username' do |username|
  @site = Site.select(:id, :username, :title, :domain, :views, :stripe_customer_id).where(username: username).first
  @title = @site.title
  not_found if @site.nil?
  erb :'surf', layout: false
end

get '/tutorials' do
  erb :'tutorials'
end

get '/donate' do
  erb :'donate'
end

post '/create_validate_all' do
  content_type :json
  fields = params.select {|p| p.match /^username$|^password$|^email$|^new_tags_string$/}

  site = Site.new fields
  return [].to_json if site.valid?
  site.errors.collect {|e| [e.first, e.last.first]}.to_json
end

post '/create_validate' do
  content_type :json

  if !params[:field].match /^username$|^password$|^email$|^new_tags_string$/
    return {error: 'not a valid field'}.to_json
  end  

  site = Site.new(params[:field] => params[:value])
  site.valid?

  field_sym = params[:field].to_sym

  if site.errors[field_sym]
    return {error: site.errors[field_sym].first}.to_json
  end

  {result: 'ok'}.to_json
end

post '/create' do
  content_type :json
  require_unbanned_ip
  dashboard_if_signed_in

  @site = Site.new(
    username: params[:username],
    password: params[:password],
    email: params[:email],
    new_tags_string: params[:tags],
    ip: request.ip
  )

  black_box_answered = BlackBox.valid? params[:blackbox_answer], request.ip
  question_answered_correctly = params[:question_answer] == session[:question_answer]

  if !question_answered_correctly
    question_first_number, question_last_number = generate_question
    return {
      result: 'bad_answer',
      question_first_number: question_first_number,
      question_last_number: question_last_number
    }.to_json
  end

  if !black_box_answered || !@site.valid? || Site.ip_create_limit?(request.ip)
    flash[:error] = 'There was an unknown error, please try again.'
    return {result: 'error'}.to_json
  end

  @site.save

  EmailWorker.perform_async({
    from: 'web@neocities.org',
    reply_to: 'contact@neocities.org',
    to: @site.email,
    subject: "[Neocities] Welcome to Neocities!",
    body: Tilt.new('./views/templates/email_welcome.erb', pretty: true).render(self)
  })

  send_confirmation_email @site

  session[:id] = @site.id
  {result: 'ok'}.to_json
end

get '/dashboard' do
  require_login

  if params[:dir] && params[:dir][0] != '/'
    params[:dir] = '/'+params[:dir]
  end

  if !File.directory?(current_site.files_path(params[:dir]))
    redirect '/dashboard'
  end

  @dir = params[:dir]
  @file_list = current_site.file_list @dir
  erb :'dashboard'
end

get '/about' do
  erb :'about'
end

require './app/api.rb'
require './app/site.rb'
require './app/site_files.rb'
require './app/admin.rb'
require './app/settings.rb'
require './app/blog.rb'
require './app/signin.rb'
require './app/tags.rb'
require './app/plan.rb'
require './app/password_reset.rb'
require './app/contact.rb'
require './app/event.rb'
require './app/comment.rb'

get '/terms' do
  erb :'terms'
end

get '/privacy' do
  erb :'privacy'
end

get '/press' do
  erb :'press'
end

post '/stripe_webhook' do
  event = JSON.parse request.body.read
  if event['type'] == 'customer.created'
    username  = event['data']['object']['description']
    email     = event['data']['object']['email']
  end
  'ok'
end