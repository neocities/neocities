require 'tilt'
require 'rss'
require 'nokogiri'
require 'pathname'

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
    application/pgp
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
    /^PUA\.Win32/,
    /^JS\.Popupper/,
    /Heuristic\.HTML\.Dropper/,
    /PHP\.Hide/
  ]

  EMAIL_SANITY_REGEX = /.+@.+\..+/i

  EDITABLE_FILE_EXT = /html|htm|txt|js|css|md/i

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
    return true if Site.where(is_banned: true).
      where(ip: ip).
      where(['updated_at > ?', Time.now-BANNED_TIME]).
      first

    return true if BlockedIp[ip]

    false
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
      File.write files_path("#{name}.html"), render_template("#{name}.erb")
      purge_cache "#{name}.html"
      ScreenshotWorker.perform_async values[:username], "#{name}.html"
    end

    FileUtils.cp template_file_path('cat.png'), files_path('cat.png')
  end

  def get_file(path)
    File.read files_path(path)
  end

  def before_destroy
    raise 'not finished'
    DB.transaction {
      remove_all_tags
      profile_comments.destroy
      profile_commentings.destroy
      follows.destroy
      followings.destroy
      #tips.destroy
      #tippings.destroy
      #blocks.destroy
      #blockings.destroy
      #reports.destroy
      #reportings.destroy
      #stats.destroy
      #events.destroy
      #site_changes.destroy
      # TODO FIND THE REST, ASSOCIATE THEM PROPERLY!!!
    }
  end

  def delete_site!
    raise 'not finished'
    DB.transaction {
      destroy
      FileUtils.mv files_path, File.join(PUBLIC_ROOT, 'deleted_sites', username)
    }
  end

  def ban!
    if username.nil? || username.empty?
      raise 'username is missing'
    end

    return if is_banned == true

    DB.transaction {
      self.is_banned = true
      self.updated_at = Time.now
      save(validate: false)
      FileUtils.mv files_path, File.join(PUBLIC_ROOT, 'banned_sites', username)
    }

    file_list.each do |path|
      purge_cache path
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

  def purge_cache(path)
    payload = {site: username, path: path}
    payload[:domain] = domain if !domain.empty?
    PurgeCacheWorker.perform_async payload
  end

  def store_file(path, uploaded)
    path = files_path(path)
    if File.exist?(path) &&
       Digest::SHA2.file(path).digest == Digest::SHA2.file(uploaded.path).digest
      return false
    end

    pathname = Pathname(path)
    if pathname.basename.to_s == 'index.html'
      new_title = Nokogiri::HTML(File.read(uploaded.path)).css('title').first.text

      if new_title.length < TITLE_MAX
        self.title = new_title
        save_changes(validate: false)
      end
    end

    dirname = pathname.dirname.to_s

    if !File.exists? dirname
      FileUtils.mkdir_p dirname
    end

    FileUtils.mv uploaded.path, path
    File.chmod 0640, path

    purge_cache path

    ext = File.extname(path).gsub(/^./, '')

    if ext.match HTML_REGEX
      ScreenshotWorker.perform_async values[:username], path
    elsif ext.match IMAGE_REGEX
      ThumbnailWorker.perform_async values[:username], path
    end

    SiteChange.record self, path

    if self.site_changed != true
      self.site_changed = true
      save_changes(validate: false)
    end

    true
  end

  def is_directory?(path)
    File.directory? files_path(path)
  end

  def create_directory(path)
    relative_path = files_path path
    if Dir.exists?(relative_path) || File.exist?(relative_path)
      return 'Directory (or file) already exists.'
    end

    FileUtils.mkdir_p relative_path
    true
  end

  def increment_changed_count
    self.changed_count += 1
    self.updated_at = Time.now
    save_changes(validate: false)
  end

  def files_zip
    zip_name = "neocities-#{username}"

    tmpfile = Tempfile.new 'neocities-site-zip'
    tmpfile.close

    Zip::Archive.open(tmpfile.path, Zip::CREATE) do |ar|
      ar.add_dir(zip_name)

      Dir.glob("#{base_files_path}/**/*").each do |path|
        relative_path = path.gsub(base_files_path+'/', '')

        if File.directory?(path)
          ar.add_dir(zip_name+'/'+relative_path)
        else
          ar.add_file(zip_name+'/'+relative_path, path) # add_file(<entry name>, <source path>)
        end
      end
    end

    tmpfile.path
  end

  def delete_file(path)
    begin
      FileUtils.rm files_path(path)
    rescue Errno::EISDIR
      FileUtils.remove_dir files_path(path), true
    rescue Errno::ENOENT
    end

    purge_cache path

    ext = File.extname(path).gsub(/^./, '')

    screenshots_delete(path) if ext.match HTML_REGEX
    thumbnails_delete(path) if ext.match IMAGE_REGEX

    SiteChangeFile.filter(site_id: self.id, filename: path).delete

    true
  end

  def move_files_from(oldusername)
    FileUtils.mv base_files_path(oldusername), base_files_path
  end

  def install_new_html_file(path)
    File.write files_path(path), render_template('index.erb')
    purge_cache path
  end

  def file_exists?(path)
    File.exist? files_path(path)
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
#    FileUtils.rm_rf files_path
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

    if values[:username].length > 32
      errors.add :username, 'User/site name cannot exceed 32 characters.'
    end

    # Check that email has been provided
    if values[:email].empty?
      errors.add :email, 'An email address is required.'
    end

    # Check for existing email
    email_check = self.class.select(:id).filter(email: values[:email]).first
    if email_check && email_check.id != self.id
      errors.add :email, 'This email address already exists on Neocities, please use your existing account instead of creating a new one.'
    end

    unless values[:email] =~ EMAIL_SANITY_REGEX
      errors.add :email, 'A valid email address is required.'
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

      if values[:domain] =~ /neocities\.org/ || values[:domain] =~ /neocitiesops\.net/
        errors.add :domain, "Domain is already being used.. by Neocities."
      end

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

  def base_files_path(name=username)
    raise 'username missing' if name.nil? || name.empty?
    File.join SITE_FILES_ROOT, name
  end

  # https://practicingruby.com/articles/implementing-an-http-file-server?u=dc2ab0f9bb
  def scrubbed_path(path='')
    path ||= ''
    clean = []

    parts = path.split '/'

    parts.each do |part|
      next if part.empty? || part == '.'
      clean << part if part != '..'
    end

    clean
  end

  def files_path(path='')
    File.join base_files_path, scrubbed_path(path)
  end

  def file_list(path='')
    list = Dir.glob(File.join(files_path(path), '*')).collect do |file_path|
      file = {
        path: file_path.gsub(base_files_path, ''),
        name: File.basename(file_path),
        ext: File.extname(file_path).gsub('.', ''),
        is_directory: File.directory?(file_path),
        is_root_index: file_path == "#{base_files_path}/index.html"
      }

      file[:is_html] = !(file[:ext].match HTML_REGEX).nil?
      file[:is_image] = !(file[:ext].match IMAGE_REGEX).nil?
      file[:is_editable] = !(file[:ext].match EDITABLE_FILE_EXT).nil?
      file
    end

    list.select {|f| f[:is_directory]}.sort_by {|f| f[:name]} +
    list.select {|f| f[:is_directory] == false}.sort_by{|f| f[:name]}
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
    Event.filter(site_id: following_ids+[self.id]).
    order(:created_at.desc).
    exclude(actioning_site_id: self.id).
    paginate(current_page, limit)
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

  def screenshots_delete(path)
    SCREENSHOT_RESOLUTIONS.each do |res|
      begin
        FileUtils.rm screenshot_path(path, res)
      rescue Errno::ENOENT
      end
    end
  end

  def thumbnails_delete(path)
    THUMBNAIL_RESOLUTIONS.each do |res|
      begin
        FileUtils.rm thumbnail_path(path, res)
      rescue Errno::ENOENT
      end
    end
  end

  def suggestions(limit=8, offset=0)
    Site.where(tags: tags).limit(limit, offset).order(:updated_at.desc).all
  end

  def screenshot_path(path, resolution)
    File.join(SCREENSHOTS_ROOT, values[:username], "#{path}.#{resolution}.jpg")
  end

  def screenshot_exists?(path, resolution)
    File.exist? File.join(SCREENSHOTS_ROOT, values[:username], "#{path}.#{resolution}.jpg")
  end

  def screenshot_url(path, resolution)
    "#{SCREENSHOTS_URL_ROOT}/#{values[:username]}/#{path}.#{resolution}.jpg"
  end

  def thumbnail_path(path, resolution)
    ext = File.extname(path).gsub('.', '').match(LOSSY_IMAGE_REGEX) ? 'jpg' : 'png'
    File.join THUMBNAILS_ROOT, values[:username], "#{path}.#{resolution}.#{ext}"
  end

  def thumbnail_exists?(path, resolution)
    File.exist? thumbnail_path(path, resolution)
  end

  def thumbnail_delete(path, resolution)
    File.rm thumbnail_path(path, resolution)
  end

  def thumbnail_url(path, resolution)
    ext = File.extname(path).gsub('.', '').match(LOSSY_IMAGE_REGEX) ? 'jpg' : 'png'
    "#{THUMBNAILS_URL_ROOT}/#{values[:username]}/#{path}.#{resolution}.#{ext}"
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
