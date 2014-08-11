require 'tilt'
require 'rss'
require 'nokogiri'

class Site < Sequel::Model
  include Sequel::ParanoidDelete

  VALID_MIME_TYPES = %w{
    text/plain
    text/html
    text/css
    application/javascript
    image/png
    image/jpeg
    image/gif
    image/svg+xml
    application/vnd.ms-fontobject
    application/x-font-ttf
    application/octet-stream
    text/csv
    text/tsv
    text/cache-manifest
    image/x-icon
    application/pdf
    application/pgp-keys
    text/xml
    application/xml
    audio/midi
  }
  VALID_EXTENSIONS = %w{
    html htm txt text css js jpg jpeg png gif svg md markdown eot ttf woff json
    geojson csv tsv mf ico pdf asc key pgp xml mid midi
  }

  ONE_MEGABYTE_IN_BYTES = 1048576
  FREE_MAXIMUM_IN_MEGABYTES = 20
  SUPPORTER_MAXIMUM_IN_MEGABYTES = 1024
  FREE_MAXIMUM_IN_BYTES = FREE_MAXIMUM_IN_MEGABYTES * ONE_MEGABYTE_IN_BYTES
  SUPPORTER_MAXIMUM_IN_BYTES = SUPPORTER_MAXIMUM_IN_MEGABYTES * ONE_MEGABYTE_IN_BYTES

  MINIMUM_PASSWORD_LENGTH = 5
  BAD_USERNAME_REGEX = /[^\w-]/i
  VALID_HOSTNAME = /^[a-z0-9][a-z0-9-]+?[a-z0-9]$/i # http://tools.ietf.org/html/rfc1123

  # FIXME smarter DIR_ROOT discovery
  DIR_ROOT             = './'
  TEMPLATE_ROOT        = File.join DIR_ROOT, 'views', 'templates'
  PUBLIC_ROOT          = File.join DIR_ROOT, 'public'
  SITE_FILES_ROOT      = File.join PUBLIC_ROOT, (ENV['RACK_ENV'] == 'test' ? 'sites_test' : 'sites')
  SCREENSHOTS_ROOT     = File.join(PUBLIC_ROOT, (ENV['RACK_ENV'] == 'test' ? 'site_screenshots_test' : 'site_screenshots'))
  THUMBNAILS_ROOT      = File.join(PUBLIC_ROOT, (ENV['RACK_ENV'] == 'test' ? 'site_thumbnails_test' : 'site_thumbnails'))
  SCREENSHOTS_URL_ROOT = '/site_screenshots'
  THUMBNAILS_URL_ROOT  = '/site_thumbnails'
  IMAGE_REGEX          = /jpg|jpeg|png|bmp|gif/
  LOSSLESS_IMAGE_REGEX = /png|bmp|gif/
  LOSSY_IMAGE_REGEX    = /jpg|jpeg/
  HTML_REGEX           = /htm|html/
  MAX_COMMENT_SIZE     = 420 # Used to be the limit for Facebook.. no comment (PUN NOT INTENDED).

  SCREENSHOT_RESOLUTIONS = ['235x141', '105x63', '270x162', '37x37', '146x88', '302x182', '90x63', '82x62', '348x205']
  THUMBNAIL_RESOLUTIONS  = ['105x63', '90x63']

  CLAMAV_THREAT_MATCHES = [
    /^VBS/,
    /^PUA.Win32/,
    /^JS.Popupper/
  ]

  BANNED_TIME = 2592000 # 30 days in seconds

  TITLE_MAX = 100

  many_to_one :server

  many_to_many :tags

  one_to_many :profile_comments
  one_to_many :profile_commentings, key: :actioning_site_id, class: :ProfileComment

  # Who is following this site
  one_to_many :follows

  # Who this site is following
  one_to_many :followings, key: :actioning_site_id, class: :Follow

  one_to_many :tips
  one_to_many :tippings, key: :actioning_site_id, class: :Tip

  one_to_many :blocks
  one_to_many :blockings, key: :actioning_site_id, class: :Block

  one_to_many :reports
  one_to_many :reportings, key: :reporting_site_id, class: :Report

  one_to_many :stats

  one_to_many :events

  one_to_many :site_changes

  class << self
    def valid_login?(username, plaintext)
      site = self[username: username]
      return false if site.nil?
      site.valid_password? plaintext
    end

    def bcrypt_cost
      @bcrypt_cost
    end

    def bcrypt_cost=(cost)
      @bcrypt_cost = cost
    end
  end

  def self.banned_ip?(ip)
    !Site.where(is_banned: true).
    where(ip: ip).
    where(['updated_at > ?', Time.now-BANNED_TIME]).
    first.nil?
  end

  def is_following?(site)
    followings_dataset.select(:id).filter(site_id: site.id).first ? true : false
  end

  def toggle_follow(site)
    if is_following? site
      follow = followings_dataset.filter(site_id: site.id).first
      site.events_dataset.filter(follow_id: follow.id).delete
      follow.delete
      false
    else
      DB.transaction do
        follow = add_following site_id: site.id
        Event.create site_id: site.id, actioning_site_id: self.id, follow_id: follow.id
      end

      true
    end
  end

  def tip_amount
    return '0.00' if tips_dataset.count == 0
    '31.337'
  end

  def username=(val)
    super val.downcase
  end

  def valid_password?(plaintext)
    BCrypt::Password.new(values[:password]) == plaintext
  end

  def password=(plaintext)
    @password_length = plaintext.nil? ? 0 : plaintext.length
    @password_plaintext = plaintext
    values[:password] = BCrypt::Password.create plaintext, cost: (self.class.bcrypt_cost || BCrypt::Engine::DEFAULT_COST)
  end

  def new_tags_string=(tags_string)
    @new_tags_string = tags_string
  end

  def before_validation
    self.server ||= Server.with_slots_available
    super
  end

  def save(validate={})
    DB.transaction do
      is_new = new?
      install_custom_domain if !domain.nil? && !domain.empty?
      result = super(validate)
      install_new_files if is_new
      result
    end
  end

  def install_custom_domain
    File.open(File.join(DIR_ROOT, 'domains', "#{username}.conf"), 'w') do |file|
      file.write render_template('domain.erb')
    end
  end

  def install_new_files
    FileUtils.mkdir_p files_path

    %w{index not_found}.each do |name|
      File.write file_path("#{name}.html"), render_template("#{name}.erb")
      PurgeCacheWorker.perform_async "#{host}/#{name}.html"
      ScreenshotWorker.perform_async values[:username], "#{name}.html"
    end

    FileUtils.cp template_file_path('cat.png'), file_path('cat.png')
  end

  def get_file(filename)
    File.read file_path(filename)
  end

  def ban!
    if username.nil? || username.empty?
      raise 'username is missing'
    end

    DB.transaction {
      FileUtils.mv files_path, File.join(PUBLIC_ROOT, 'banned_sites', username)
      self.is_banned = true
      self.updated_at = Time.now
      save(validate: false)
    }

    site_files.file_list.collect {|f| f.filename}.each do |f|
      PurgeCacheWorker.async_queue "#{host}/#{f}"
    end
  end

=begin
  def follows_dataset
    super.where(Sequel.~(site_id: blocking_site_ids))
    .where(Sequel.~(actioning_site_id: blocking_site_ids))
  end

  def followings_dataset
    super.where(Sequel.~(site_id: blocking_site_ids))
    .where(Sequel.~(actioning_site_id: blocking_site_ids))
  end

  def events_dataset
    super.where(Sequel.~(site_id: blocking_site_ids))
    .where(Sequel.~(actioning_site_id: blocking_site_ids))
  end
=end

  def blocking_site_ids
    @blocking_site_ids ||= blockings_dataset.select(:site_id).all.collect {|s| s.site_id}
  end

  def block!(site)
    block = blockings_dataset.filter(site_id: site.id).first
    DB.transaction do
      add_blocking site: site
    end
  end

  def is_blocking?(site)
    @blockings ||= blockings
    !@blockings.select {|b| b.site_id == site.id}.empty?
  end

  def self.valid_filename?(filename)
    return false if sanitize_filename(filename) != filename
    true
  end

  def self.sanitize_filename(filename)
    filename.gsub(/[^a-zA-Z0-9_\-.]/, '')
  end

  def self.valid_username?(username)
    !username.empty? && username.match(/^[a-zA-Z0-9_\-]+$/i)
  end

  def self.valid_file_type?(uploaded_file)
    mime_type = Magic.guess_file_mime_type uploaded_file[:tempfile].path

    return false unless (Site::VALID_MIME_TYPES.include?(mime_type) || mime_type =~ /text/) &&
                        Site::VALID_EXTENSIONS.include?(File.extname(uploaded_file[:filename]).sub(/^./, '').downcase)

    # clamdscan doesn't work on travis for testing
    return true if ENV['TRAVIS'] == 'true'

    File.chmod 0640, uploaded_file[:tempfile].path
    line = Cocaine::CommandLine.new(
      "clamdscan", "-i --remove=no --no-summary --stdout :path",
      expected_outcodes: [0, 1]
    )

    output = line.run path: uploaded_file[:tempfile].path

    return true if output == ''

    threat = output.strip.match(/^.+: (.+) FOUND$/).captures.first

    CLAMAV_THREAT_MATCHES.each do |threat_match|
      return false if threat.match threat_match
    end

    true
  end

  def store_file(filename, uploaded)
    if File.exist?(file_path(filename)) &&
       Digest::SHA2.file(file_path(filename)).digest == Digest::SHA2.file(uploaded.path).digest
      return false
    end

    if filename == 'index.html'
      new_title = Nokogiri::HTML(File.read(uploaded.path)).css('title').first.text

      if new_title.length < TITLE_MAX
        self.title = new_title
        save_changes(validate: false)
      end
    end

    FileUtils.mv uploaded.path, file_path(filename)
    File.chmod(0640, file_path(filename))

    PurgeCacheWorker.perform_async "#{host}/#{filename}"

    ext = File.extname(filename).gsub(/^./, '')

    if ext.match HTML_REGEX
      ScreenshotWorker.perform_async values[:username], filename
    elsif ext.match IMAGE_REGEX
      ThumbnailWorker.perform_async values[:username], filename
    end

    SiteChange.record self, filename

    if self.site_changed != true
      self.site_changed = true
      save_changes(validate: false)
    end

    true
  end

  def increment_changed_count
    self.changed_count += 1
    self.updated_at = Time.now
    save_changes(validate: false)
  end

  def files_zip
    file_path = "/tmp/neocities-site-#{username}.zip"

    Zip::File.open(file_path, Zip::File::CREATE) do |zipfile|
      file_list.collect {|f| f.filename}.each do |filename|
        zipfile.add filename, file_path(filename)
      end
    end

    # TODO Don't dump the zipfile into memory
    zipfile = File.read file_path
    File.delete file_path
    zipfile
  end

  def delete_file(filename)
    begin
      FileUtils.rm file_path(filename)
    rescue Errno::ENOENT
    end

    PurgeCacheWorker.perform_async "#{host}/#{filename}"

    ext = File.extname(filename).gsub(/^./, '')

    screenshots_delete(filename) if ext.match HTML_REGEX
    thumbnails_delete(filename) if ext.match IMAGE_REGEX

    SiteChangeFile.filter(site_id: self.id, filename: filename).delete

    true
  end

  def move_files_from(oldusername)
    FileUtils.mv files_path(oldusername), files_path
  end

  def install_new_html_file(name)
    File.write file_path(name), render_template('index.erb')
    PurgeCacheWorker.perform_async "#{host}/#{name}"
  end

  def file_exists?(filename)
    File.exist? file_path(filename)
  end

  def after_save
    if @new_filtered_tags
      @new_filtered_tags.each do |new_tag_string|
        add_tag_name new_tag_string
      end
      @new_filtered_tags = []
      @new_tags_string = nil
    end
    super
  end

  def add_tag_name(name)
    add_tag Tag[name: name] || Tag.create(name: name)
  end

  def after_create
    DB['update servers set slots_available=slots_available-1 where id=?', self.server.id].first
    super
  end

  def before_create
    self.email_confirmation_token = SecureRandom.hex 3
    super
  end

#  def after_destroy
#    FileUtils.rm_rf file_path
#    super
#  end

  def validate
    super

    if server.nil?
      errors.add :over_capacity, 'We are currently at capacity, and cannot create your home page. We will fix this shortly. Please come back later and try again, our apologies.'
    end

    if !self.class.valid_username?(values[:username])
      errors.add :username, 'A valid user/site name is required.'
    end

    # TODO regex fails for usernames <= 2 chars, tempfix for now.
    if new? && values[:username].length > 2 && !values[:username].match(VALID_HOSTNAME)
      errors.add :username, 'A valid user/site name is required.'
    end

    if new? && values[:username].length > 32
      errors.add :username, 'User/site name cannot exceed 32 characters.'
    end

    # Check that email has been provided
    if new? && values[:email].empty?
      errors.add :email, 'An email address is required.'
    end

    # Check for existing email
    if new? && self.class.select(:id).filter(email: values[:email]).first
      errors.add :email, 'This email address already exists on Neocities, please use your existing account.'
    end

    # Check for existing user
    user = self.class.select(:id, :username).filter(username: values[:username]).first

    if user
      if user.id != values[:id]
        errors.add :username, 'This username is already taken. Try using another one.'
      end
    end

    if values[:password].nil? || (@password_length && @password_length < MINIMUM_PASSWORD_LENGTH)
      errors.add :password, "Password must be at least #{MINIMUM_PASSWORD_LENGTH} characters."
    end

    if !values[:domain].nil? && !values[:domain].empty?
      if !(values[:domain] =~ /^[a-zA-Z0-9.-]+\.[a-zA-Z0-9]+$/i) || values[:domain].length > 90
        errors.add :domain, "Domain provided is not valid. Must take the form of domain.com"
      end

      site = Site[domain: values[:domain]]
      if !site.nil? && site.id != self.id
        errors.add :domain, "Domain provided is already being used by another site, please choose another."
      end
    end

    if @new_tags_string
      new_tags = @new_tags_string.split ','
      new_tags.compact!
      @new_filtered_tags = []

      if ((new? ? 0 : tags_dataset.count) + new_tags.length > 5)
        errors.add :tags, 'Cannot have more than 5 tags for your site.'
      end

      new_tags.each do |tag|
        tag.strip!
        if tag.match(/[^a-zA-Z0-9 ]/)
          errors.add :tags, "Tag \"#{tag}\" can only contain letters (A-Z) and numbers (0-9)."
          break
        end

        if tag.length > Tag::NAME_LENGTH_MAX
          errors.add :tags, "Tag \"#{tag}\" cannot be longer than #{Tag::NAME_LENGTH_MAX} characters."
          break
        end

        if tag.match(/  /)
          errors.add :tags, "Tag \"#{tag}\" cannot have spaces."
          break
        end

        if tag.split(' ').length > Tag::NAME_WORDS_MAX
          errors.add :tags, "Tag \"#{tag}\" cannot be more than #{Tag::NAME_WORDS_MAX} word."
          break
        end

        next if tags.collect {|t| t.name}.include? tag

        @new_filtered_tags << tag
        @new_filtered_tags.uniq!
      end
    end
  end

  def render_template(name)
    Tilt.new(template_file_path(name), pretty: true).render self
  end

  def template_file_path(name)
    File.join TEMPLATE_ROOT, name
  end

  def files_path(name=nil)
    File.join SITE_FILES_ROOT, (name || username)
  end

  def file_path(filename)
    File.join files_path, filename
  end

  def file_list
    Dir.glob(File.join(files_path, '*')).collect {|p| File.basename(p)}.sort.collect {|sitename| SiteFile.new sitename}
  end

  def file_size_too_large?(size_in_bytes)
    return true if size_in_bytes + used_space_in_bytes > maximum_space_in_bytes
    false
  end

  def used_space_in_bytes
    space = Dir.glob(File.join(files_path, '*')).collect {|p| File.size(p)}.inject {|sum,x| sum += x}
    space.nil? ? 0 : space
  end

  def used_space_in_megabytes
    (used_space_in_bytes.to_f / self.class::ONE_MEGABYTE_IN_BYTES).round(2)
  end

  def available_space_in_bytes
    remaining = maximum_space_in_bytes - used_space_in_bytes
    remaining < 0 ? 0 : remaining
  end

  def available_space_in_megabytes
    (available_space_in_bytes.to_f / self.class::ONE_MEGABYTE_IN_BYTES).round(2)
  end

  def maximum_space_in_bytes
    supporter? ? self.class::SUPPORTER_MAXIMUM_IN_BYTES : self.class::FREE_MAXIMUM_IN_BYTES
  end

  def maximum_space_in_megabytes
    supporter? ? self.class::SUPPORTER_MAXIMUM_IN_MEGABYTES : self.class::FREE_MAXIMUM_IN_MEGABYTES
  end

  def space_percentage_used
    ((used_space_in_bytes.to_f / maximum_space_in_bytes) * 100).round(1)
  end

  # This returns true even if they end their support plan.
  def supporter?
    !values[:stripe_customer_id].nil?
  end

  # This will return false if they have ended their support plan.
  def ended_supporter?
    values[:ended_plan]
  end

  def plan_name
    return 'Free Plan' if !supporter? || (supporter? && ended_supporter?)
    'Supporter Plan'
  end

  def latest_events(current_page=1, limit=10)
    events_dataset.order(:created_at.desc).paginate(current_page, limit)
  end

  def news_feed(current_page=1, limit=10)
    following_ids = self.followings_dataset.select(:site_id).all.collect {|f| f.site_id}
    Event.filter(site_id: following_ids+[self.id]).order(:created_at.desc).paginate(current_page, limit)
  end

  def host
    !domain.empty? ? domain : "#{username}.neocities.org"
  end

  def title
    if values[:title].nil? || values[:title].empty?
      domain ? domain : "#{username}.neocities.org"
    else
      values[:title]
    end
  end

  def hits_english
    values[:hits].to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
  end

  def screenshots_delete(filename)
    SCREENSHOT_RESOLUTIONS.each do |res|
      begin
        FileUtils.rm screenshot_path(filename, res)
      rescue Errno::ENOENT
      end
    end
  end

  def thumbnails_delete(filename)
    THUMBNAIL_RESOLUTIONS.each do |res|
      begin
        FileUtils.rm thumbnail_path(filename, res)
      rescue Errno::ENOENT
      end
    end
  end

  def suggestions(limit=8, offset=0)
    Site.where(tags: tags).limit(limit, offset).order(:updated_at.desc).all
  end

  def screenshot_path(filename, resolution)
    File.join(SCREENSHOTS_ROOT, values[:username], "#{filename}.#{resolution}.jpg")
  end

  def screenshot_exists?(filename, resolution)
    File.exist? File.join(SCREENSHOTS_ROOT, values[:username], "#{filename}.#{resolution}.jpg")
  end

  def screenshot_url(filename, resolution)
    "#{SCREENSHOTS_URL_ROOT}/#{values[:username]}/#{filename}.#{resolution}.jpg"
  end

  def thumbnail_path(filename, resolution)
    ext = File.extname(filename).gsub('.', '').match(LOSSY_IMAGE_REGEX) ? 'jpg' : 'png'
    File.join THUMBNAILS_ROOT, values[:username], "#{filename}.#{resolution}.#{ext}"
  end

  def thumbnail_exists?(filename, resolution)
    File.exist? thumbnail_path(filename, resolution)
  end

  def thumbnail_delete(filename, resolution)
    File.rm thumbnail_path(filename, resolution)
  end

  def thumbnail_url(filename, resolution)
    ext = File.extname(filename).gsub('.', '').match(LOSSY_IMAGE_REGEX) ? 'jpg' : 'png'
    "#{THUMBNAILS_URL_ROOT}/#{values[:username]}/#{filename}.#{resolution}.#{ext}"
  end

  def to_rss
    RSS::Maker.make("atom") do |maker|
      maker.channel.title   = title
      maker.channel.updated = updated_at
      maker.channel.author  = username
      maker.channel.id      = "#{username}.neocities.org"

      latest_events.each do |event|
        if event.site_change_id
          maker.items.new_item do |item|
            item.link = "http://#{username}.neocities.org"
            item.title = "#{username}.neocities.org has been updated"
            item.updated = event.site_change.created_at
          end
        end
      end
    end
  end
end
