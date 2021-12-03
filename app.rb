require './environment.rb'
require './app_helpers.rb'

use Rack::Session::Cookie, key:          'neocities',
                           path:         '/',
                           expire_after: 31556926, # one year in seconds
                           secret:       $config['session_secret'],
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
  yosemite
}.freeze

def redirect_to_internet_archive_for_geocities_sites
  match = request.path.match /^\/(\w+)\/.+$/i
  if match && GEOCITIES_NEIGHBORHOODS.include?(match.captures.first.downcase)
    redirect "https://wayback.archive.org/http://geocities.com/#{request.path}"
  end
end

before do
  if request.path.match /^\/api\//i
    @api = true
    content_type :json
  elsif request.path.match /^\/webhooks\//
    # Skips the CSRF/validation check for stripe web hooks
  elsif email_not_validated? && !(request.path =~ /^\/site\/.+\/confirm_email|^\/settings\/change_email|^\/signout|^\/welcome|^\/supporter/)
    redirect "/site/#{current_site.username}/confirm_email"
  else
    content_type :html, 'charset' => 'utf-8'
    redirect '/' if request.post? && !csrf_safe?
  end
end

after do
  if @api
    request.session_options[:skip] = true
  end
end

#after do
  #response.headers['Content-Security-Policy'] = %{block-all-mixed-content; default-src 'self'; connect-src 'self' https://api.stripe.com https://assets.hcaptcha.com; frame-src https://assets.hcaptcha.com https://js.stripe.com; script-src 'self' 'unsafe-inline' https://js.stripe.com https://hcaptcha.com https://assets.hcaptcha.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: }
#end

not_found do
  api_not_found if @api
  redirect_to_internet_archive_for_geocities_sites
  @title = 'Not Found'
  erb :'not_found'
end

error do
  EmailWorker.perform_async({
    from: 'web@neocities.org',
    to: 'errors@neocities.org',
    subject: "[Neocities Error] #{env['sinatra.error'].class}: #{env['sinatra.error'].message}",
    body: erb(:'templates/email/error', layout: false),
    no_footer: true
  })

  if @api
    api_error 500, 'server_error', 'there has been an unknown server error, please try again later'
  end

  erb :'error'
end

Dir['./app/**/*.rb'].each {|f| require f}
