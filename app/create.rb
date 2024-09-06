CREATE_MATCH_REGEX = /^username$|^password$|^email$|^new_tags_string$|^is_education$/

def education_whitelist_required?
  return true if params[:is_education] == 'true' && $config['education_tag_whitelist']
  false
end

def education_whitelisted?
  return true if education_whitelist_required? && !$config['education_tag_whitelist'].select {|t| params[:new_tags_string].match(t)}.empty?
  false
end

post '/create_validate_all' do
  content_type :json
  fields = params.select {|p| p.match CREATE_MATCH_REGEX}

  begin
    site = Site.new fields
  rescue ArgumentError => e
    if e.message == 'input string invalid'
      return {error: 'invalid input'}.to_json
    else
      raise e
    end
  end

  if site.valid?
    return [].to_json if education_whitelisted?
  end

  resp = site.errors.collect {|e| [e.first, e.last.first]}
  resp << ['captcha', 'Please complete the captcha.'] if params[:'h-captcha-response'].empty? && !self.class.test?
  resp.to_json
end

post '/create_validate' do
  content_type :json

  if !params[:field].match CREATE_MATCH_REGEX
    return {error: 'not a valid field'}.to_json
  end

  begin
    site = Site.new(params[:field] => params[:value])
  rescue ArgumentError => e
    if e.message == 'input string invalid'
      return {error: 'invalid input'}.to_json
    else
      raise e
    end
  end

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
  dashboard_if_signed_in

  @site = Site.new(
    username: params[:username],
    password: params[:password],
    email: params[:email],
    new_tags_string: params[:new_tags_string],
    is_education: params[:is_education] == 'true' ? true : false,
    ip: request.ip,
    ga_adgroupid: session[:ga_adgroupid]
  )

  if education_whitelist_required?
    if education_whitelisted?
      @site.email_confirmed = true
    else
      flash[:error] = 'The class tag is invalid.'
      return {result: 'error'}.to_json
    end
  else
    if !hcaptcha_valid?
      flash[:error] = 'The captcha was not valid, please try again.'
      return {result: 'error'}.to_json
    end

    if Site.ip_create_limit?(request.ip)
      flash[:error] = 'Your IP address has created too many sites, please try again later or contact support.'
      return {result: 'error'}.to_json
    end

    if Site.disposable_mx_record?(@site.email)
      flash[:error] = 'Cannot use a disposable email address.'
      return {result: 'error'}.to_json
    end

    if defined?(BlackBox.create_disabled?) && BlackBox.create_disabled?(@site, request)
      flash[:error] = 'Site creation is not currently available from your location, please try again later.'
      return {result: 'error'}.to_json
    end

    if defined?(BlackBox.tutorial_required?) && BlackBox.tutorial_required?(@site, request)
      @site.tutorial_required = true
    end

    if !@site.valid?
      flash[:error] = @site.errors.first.last.first
      return {result: 'error'}.to_json
    end
  end

  @site.email_confirmed = true if self.class.development?
  @site.phone_verified = true if self.class.development?

  begin
    @site.phone_verification_required = true if self.class.production? && BlackBox.phone_verification_required?(@site)
  rescue => e
    EmailWorker.perform_async({
      from: 'web@neocities.org',
      to: 'errors@neocities.org',
      subject: "[Neocities Error] Phone verification exception",
      body: "#{e.inspect}\n#{e.backtrace}",
      no_footer: true
    })
  end

  begin
    @site.save
  rescue Sequel::UniqueConstraintViolation => e
    if e.message =~ /username.+already exists/
      flash[:error] = 'Username already exists.'
      return {result: 'error'}.to_json
    end

    raise e
  end

  unless education_whitelisted?
    @site.send_email(
      subject: "[Neocities] Welcome to Neocities!",
      body: Tilt.new('./views/templates/email/welcome.erb', pretty: true).render(self)
    )

    send_confirmation_email @site
  end

  session[:id] = @site.id
  {result: 'ok'}.to_json
end
