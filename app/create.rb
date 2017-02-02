def new_recaptcha_valid?
  return true if ENV['RACK_ENV'] == 'test' || ENV['TRAVIS']
  return false unless params[:'g-recaptcha-response']
  resp = Net::HTTP.get URI(
    'https://www.google.com/recaptcha/api/siteverify?'+
    Rack::Utils.build_query(
      secret: $config['recaptcha_private_key'],
      response: params[:'g-recaptcha-response']
    )
  )

  if JSON.parse(resp)['success'] == true
    true
  else
    false
  end
end

CREATE_MATCH_REGEX = /^username$|^password$|^email$|^new_tags_string$|^is_education$/

def education_whitelisted?
  return true if params[:is_education] == 'true' && $config['education_tag_whitelist'] && !$config['education_tag_whitelist'].select {|t| params[:new_tags_string].match(t)}.empty?
  false
end

post '/create_validate_all' do
  content_type :json
  fields = params.select {|p| p.match CREATE_MATCH_REGEX}

  site = Site.new fields

  if site.valid?
    return [].to_json if education_whitelisted? || params[:'g-recaptcha-response']
    return [['captcha', 'Please complete the captcha.']].to_json
  end

  site.errors.collect {|e| [e.first, e.last.first]}.to_json
end

post '/create_validate' do
  content_type :json

  if !params[:field].match CREATE_MATCH_REGEX
    return {error: 'not a valid field'}.to_json
  end

  site = Site.new(params[:field] => params[:value])
  site.is_education = params[:is_education]
  site.valid?

  field_sym = params[:field].to_sym

  if site.errors[field_sym]
    return {error: site.errors[field_sym].first}.to_json
  end

  {result: 'ok'}.to_json
end

post '/create' do
  content_type :json

  if banned?(true)
    signout
    session[:banned] = true if !session[:banned]

    flash[:error] = 'There was an error, please <a href="/contact">contact support</a> to log in.'
    redirect '/'
  end

  dashboard_if_signed_in

  @site = Site.new(
    username: params[:username],
    password: params[:password],
    email: params[:email],
    new_tags_string: params[:new_tags_string],
    is_education: params[:is_education] == 'true' ? true : false,
    ip: request.ip
  )

  if education_whitelisted?
    @site.email_confirmed = true
  else
    if !new_recaptcha_valid?
      flash[:error] = 'The captcha was not valid, please try again.'
      return {result: 'error'}.to_json
    end

    if !@site.valid? || Site.ip_create_limit?(request.ip)
      flash[:error] = 'Your IP address has created too many sites, please try again later or contact support.'
      return {result: 'error'}.to_json
    end

    if Site.disposable_mx_record?(@site.email)
      flash[:error] = 'Cannot use a disposable email address.'
      return {result: 'error'}.to_json
    end
  end

  @site.email_confirmed = true if self.class.development?
  @site.save

  unless education_whitelisted?
    @site.send_email(
      subject: "[Neocities] Welcome to Neocities!",
      body: Tilt.new('./views/templates/email_welcome.erb', pretty: true).render(self)
    )

    send_confirmation_email @site
  end

  session[:id] = @site.id
  {result: 'ok'}.to_json
end
