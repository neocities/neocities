def new_recaptcha_valid?
  return session[:captcha_valid] = true if ENV['RACK_ENV'] == 'test'
  resp = Net::HTTP.get URI(
    'https://www.google.com/recaptcha/api/siteverify?'+
    Rack::Utils.build_query(
      secret: $config['recaptcha_private_key'],
      response: params[:'g-recaptcha-response']
    )
  )

  if JSON.parse(resp)['success'] == true
    session[:captcha_valid] = true
    true
  else
    false
  end
end

post '/create_validate_all' do
  content_type :json
  fields = params.select {|p| p.match /^username$|^password$|^email$|^new_tags_string$/}

  site = Site.new fields

  if site.valid?
    return [].to_json if new_recaptcha_valid?
    return [['captcha', 'Please complete the captcha.']].to_json
  end

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

  if session[:captcha_valid] != true
    flash[:error] = 'The captcha was not valid, please try again.'
    return {result: 'error'}.to_json
  end

  if !@site.valid? || Site.ip_create_limit?(request.ip)
    flash[:error] = 'There was an unknown error, please try again.'
    return {result: 'error'}.to_json
  end

  @site.save

  session[:captcha_valid] = nil

  @site.send_email(
    subject: "[Neocities] Welcome to Neocities!",
    body: Tilt.new('./views/templates/email_welcome.erb', pretty: true).render(self)
  )

  send_confirmation_email @site

  session[:id] = @site.id
  {result: 'ok'}.to_json
end