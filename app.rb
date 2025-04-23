require './environment.rb'
require './app_helpers.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       Base64.strict_decode64($config['session_secret']),
                           httponly: true,
                           same_site: :lax,
                           secure: ENV['RACK_ENV'] == 'production'

use Rack::TempfileReaper

helpers do
  def site_change_file_display_class(filename)
    return 'html' if filename.match(Site::HTML_REGEX)
    return 'image' if filename.match(Site::IMAGE_REGEX)
    'misc'
  end

  def csrf_token_input_html
    %{<input name="csrf_token" type="hidden" value="#{csrf_token}">}
  end

  def hcaptcha_input
    %{
      <script src="https://hcaptcha.com/1/api.js" async defer></script>
      <div id="captcha_input" class="h-captcha" data-sitekey="#{$config['hcaptcha_site_key']}"></div>
    }
  end
end

set :protection, :frame_options => "DENY"

GEOCITIES_NEIGHBORHOODS = %w{
  area51
  athens
  augusta
  baja
  bourbonstreet
  capecanaveral
  capitolhill
  collegepark
  colosseum
  enchantedforest
  hollywood
  motorcity
  napavalley
  nashville
  petsburgh
  pipeline
  rainforest
  researchtriangle
  siliconvalley
  soho
  sunsetstrip
  timessquare
  televisioncity
  tokyo
  vienna
  westhollywood
  yosemite
}.freeze

def redirect_to_internet_archive_for_geocities_sites
  match = request.path.match /^\/(\w+)\/.+$/i
  if match && GEOCITIES_NEIGHBORHOODS.include?(match.captures.first.downcase)
    redirect "https://wayback.archive.org/http://geocities.com/#{request.path}"
  end
end

WHITELISTED_POST_PATHS = ['/create_validate_all', '/create_validate', '/create'].freeze

before do
  if request.path.match /^\/api\//i
    @api = true
    content_type :json
  elsif request.path.match /^\/webhooks\//
    # Skips the CSRF/validation check for stripe web hooks
  elsif current_site && current_site.email_not_validated? && !(request.path =~ /^\/site\/.+\/confirm_email|^\/settings\/change_email|^\/welcome|^\/supporter|^\/signout/)
    redirect "/site/#{current_site.username}/confirm_email"
  elsif current_site && current_site.phone_verification_needed? && !(request.path =~ /^\/site\/.+\/confirm_email|^\/settings\/change_email|^\/site\/.+\/confirm_phone|^\/welcome|^\/supporter|^\/signout/)
    redirect  "/site/#{current_site.username}/confirm_phone"
  elsif current_site && current_site.tutorial_required && !(request.path =~ /^\/site\/.+\/confirm_email|^\/settings\/change_email|^\/site\/.+\/confirm_phone|^\/welcome|^\/supporter|^\/tutorial\/.+/)
    redirect '/tutorial/html/1'
  else
    content_type :html, 'charset' => 'utf-8'
    redirect '/' if request.post? && !WHITELISTED_POST_PATHS.include?(request.path_info) && !csrf_safe?
  end

  if params[:page]
    params[:page] = params[:page].to_s
    unless params[:page] =~ /^\d+$/ && params[:page].to_i > 0
      params[:page] = '1'
    end
  end

  if params[:tag]
    begin
      params.delete 'tag' if params[:tag].nil? || !params[:tag].is_a?(String) || params[:tag].strip.empty? || params[:tag].match?(Tag::INVALID_TAG_REGEX)
    rescue Encoding::CompatibilityError, ArgumentError
      params.delete 'tag'
    end
  end
end

after do
  if @api
    request.session_options[:skip] = true
  else
    # Set issue timestamp on session cookie if it doesn't exist yet
    session['i'] = Time.now.to_i if session && !session['i'] && session['id']
  end

  unless self.class.development?
    response.headers['Content-Security-Policy'] = %{default-src 'self' data: blob: 'unsafe-inline'; script-src 'self' blob: 'unsafe-inline' 'unsafe-eval' https://hcaptcha.com https://*.hcaptcha.com https://js.stripe.com; style-src 'self' 'unsafe-inline' https://hcaptcha.com https://*.hcaptcha.com; connect-src 'self' https://hcaptcha.com https://*.hcaptcha.com https://api.stripe.com; frame-src 'self' https://hcaptcha.com https://*.hcaptcha.com https://js.stripe.com}
  end
end

not_found do
  api_not_found if @api
  redirect_to_internet_archive_for_geocities_sites
  @title = 'Not Found'
  erb :'not_found'
end

error do
=begin
  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'errors@neocities.org',
    subject: "[Neocities Error] #{env['sinatra.error'].class}: #{env['sinatra.error'].message}",
    body: erb(:'templates/email/error', layout: false),
    no_footer: true
  })
=end

  if @api
    api_error 500, 'server_error', 'there has been an unknown server error, please try again later'
  end

  erb :'error'
end

Dir['./app/**/*.rb'].each {|f| require f}
