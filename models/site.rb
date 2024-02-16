# frozen_string_literal: true
require 'tilt'
require 'nokogiri'
require 'pathname'
require 'zlib'

class Site < Sequel::Model
  include Sequel::ParanoidDelete

  VALID_MIME_TYPES = %w{
    text/plain
    text/html
    text/css
    application/javascript
    image/png
    image/apng
    image/jpeg
    image/gif
    image/svg
    image/svg+xml
    application/vnd.ms-fontobject
    application/x-font-ttf
    application/vnd.ms-opentype
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
    text/cache-manifest
    application/rss+xml
    application/x-elc
    image/webp
    image/avif
    image/x-xcf
    application/epub
    application/epub+zip
    message/rfc822
    application/font-sfnt
    application/opensearchdescription+xml
  }

  VALID_EXTENSIONS = %w{
    html htm txt text css js jpg jpeg png apng gif svg md markdown eot ttf woff woff2 json geojson csv tsv mf ico pdf asc key pgp xml mid midi manifest otf webapp less sass rss kml dae obj mtl scss webp avif xcf epub gltf bin webmanifest knowl atom opml rdf map gpg resolveHandle pls yaml yml toml osdx
  }

  VALID_EDITABLE_EXTENSIONS = %w{
    html htm txt js css scss md manifest less webmanifest xml json opml rdf svg gpg pgp resolveHandle pls yaml yml toml osdx
  }

  MINIMUM_PASSWORD_LENGTH = 5
  BAD_USERNAME_REGEX = /[^\w-]/i
  VALID_HOSTNAME = /^[a-z0-9][a-z0-9-]+?[a-z0-9]$/i # http://tools.ietf.org/html/rfc1123

  # FIXME smarter DIR_ROOT discovery
  DIR_ROOT               = './'
  TEMPLATE_ROOT          = File.join DIR_ROOT, 'views', 'templates'
  PUBLIC_ROOT            = File.join DIR_ROOT, 'public'
  SITE_FILES_ROOT        = File.join PUBLIC_ROOT, (ENV['RACK_ENV'] == 'test' ? 'sites_test' : 'sites')
  SCREENSHOTS_ROOT       = File.join(PUBLIC_ROOT, (ENV['RACK_ENV'] == 'test' ? 'site_screenshots_test' : 'site_screenshots'))
  THUMBNAILS_ROOT        = File.join(PUBLIC_ROOT, (ENV['RACK_ENV'] == 'test' ? 'site_thumbnails_test' : 'site_thumbnails'))
  SCREENSHOTS_URL_ROOT   = ENV['RACK_ENV'] == 'test' ? '/site_screenshots_test' : '/site_screenshots'
  THUMBNAILS_URL_ROOT    = ENV['RACK_ENV'] == 'test' ? '/site_thumbnails_test' : '/site_thumbnails'
  DELETED_SITES_ROOT     = File.join PUBLIC_ROOT, 'deleted_sites'
  BANNED_SITES_ROOT      = File.join PUBLIC_ROOT, 'banned_sites'
  IMAGE_REGEX            = /jpg|jpeg|png|bmp|gif/
  LOSSLESS_IMAGE_REGEX   = /png|bmp|gif/
  LOSSY_IMAGE_REGEX      = /jpg|jpeg/
  HTML_REGEX             = /.html$|.htm$/
  INDEX_HTML_REGEX       = /\/?index.html$/
  ROOT_INDEX_HTML_REGEX  = /^\/?index.html$/
  MAX_COMMENT_SIZE       = 420 # Used to be the limit for Facebook.. no comment (PUN NOT INTENDED).
  MAX_FOLLOWS            = 1000
  
  BROWSE_MINIMUM_VIEWS   = 100
  BROWSE_MINIMUM_FOLLOWER_VIEWS = 10_000

  SCREENSHOT_DELAY_SECONDS = 30
  SCREENSHOT_RESOLUTIONS   = ['540x405', '210x158', '100x100', '50x50']
  THUMBNAIL_RESOLUTIONS    = ['210x158']

  MAX_FILE_SIZE = 10**8 # 100 MB

  CLAMAV_THREAT_MATCHES = [
    /^VBS/,
    /^PUA\.Win32/,
    /^JS\.Popupper/,
    /Heuristic\.HTML\.Dropper/,
    /PHP\.Hide/
  ]

  EMPTY_FILE_HASH = Digest::SHA1.hexdigest ''

  EMAIL_SANITY_REGEX = /.+@.+\..+/i
  EDITABLE_FILE_EXT = /#{VALID_EDITABLE_EXTENSIONS.join('|')}/i
  BANNED_TIME = 2592000 # 30 days in seconds
  TITLE_MAX = 100

  COMMENTING_ALLOWED_UPDATED_COUNT = 2

  SUGGESTIONS_LIMIT = 30
  SUGGESTIONS_VIEWS_MIN = 500
  CHILD_SITES_MAX = 30

  IP_CREATE_LIMIT = 1000
  TOTAL_IP_CREATE_LIMIT = 10000

  FROM_EMAIL = 'noreply@neocities.org'

  PLAN_FEATURES = {}

  PLAN_FEATURES[:supporter] = {
    name: 'Supporter',
    space: Filesize.from('50GB'),
    bandwidth: Filesize.from('3TB'),
    price: 5,
    unlimited_site_creation: true,
    custom_ssl_certificates: true,
    no_file_restrictions: true,
    custom_domains: true,
    maximum_site_files: 100_000
  }

  PLAN_FEATURES[:free] = PLAN_FEATURES[:supporter].merge(
    name: 'Free',
    space: Filesize.from('1GB'),
    bandwidth: Filesize.from('200GB'),
    price: 0,
    unlimited_site_creation: false,
    custom_ssl_certificates: false,
    no_file_restrictions: false,
    custom_domains: false,
    maximum_site_files: 15_000
  )

  EMAIL_VALIDATION_CUTOFF_DATE = Time.parse('May 16, 2016')
  DISPOSABLE_EMAIL_BLACKLIST_PATH = File.join(DIR_ROOT, 'files', 'disposable_email_blacklist.conf')
  BANNED_EMAIL_BLACKLIST_PATH = File.join(DIR_ROOT, 'files', 'banned_email_blacklist.conf')

  BLOCK_JERK_PERCENTAGE = 30
  BLOCK_JERK_THRESHOLD = 25
  MAXIMUM_TAGS = 5
  MAX_USERNAME_LENGTH = 32

  LEGACY_SUPPORTER_PRICES = {
    plan_one: 1,
    plan_two: 2,
    plan_three: 3,
    plan_four: 4,
    plan_five: 5
  }

  BROWSE_PAGINATION_LENGTH = 100
  EMAIL_BLAST_MAXIMUM_AGE = 6.months.ago

  if ENV['RACK_ENV'] == 'test'
    EMAIL_BLAST_MAXIMUM_PER_DAY = 2
  else
    EMAIL_BLAST_MAXIMUM_PER_DAY = 1000
  end

  MAXIMUM_EMAIL_CONFIRMATIONS = 20
  MAX_COMMENTS_PER_DAY = 5
  SANDBOX_TIME = 14.days
  BLACK_BOX_WAIT_TIME = 10.seconds
  MAX_DISPLAY_FOLLOWS = 56*3

  PHONE_VERIFICATION_EXPIRATION_TIME = 10.minutes
  PHONE_VERIFICATION_LOCKOUT_ATTEMPTS = 3

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

  many_to_one :parent, :key => :parent_site_id, :class => self
  one_to_many :children, :key => :parent_site_id, :class => self

  one_to_many :site_files

  one_to_many :stats
  one_to_many :stat_referrers
  one_to_many :stat_locations
  one_to_many :stat_paths

  def self.supporter_ids
    parent_supporters = DB[%{SELECT id FROM sites WHERE plan_type IS NOT NULL AND plan_type != 'free'}].all.collect {|s| s[:id]}
    child_supporters = DB[%{select a.id as id from sites a, sites b where a.parent_site_id is not null and a.parent_site_id=b.id and (a.plan_type != 'free' or b.plan_type != 'free')}].all.collect {|s| s[:id]}
    parent_supporters + child_supporters
  end

  def self.newsletter_sites
     Site.select(:email).
       exclude(email: 'nil').exclude(is_banned: true).
       where{updated_at > EMAIL_BLAST_MAXIMUM_AGE}.
       where{changed_count > 0}.
       order(:updated_at.desc).
       all
  end

  def too_many_files?(file_count=0)
    (site_files_dataset.count + file_count) > plan_feature(:maximum_site_files)
  end

  def plan_feature(key)
    PLAN_FEATURES[plan_type.to_sym][key.to_sym]
  end

  def custom_domain_available?
    owner.plan_feature(:custom_domains) == true || !domain.nil?
  end

  def account_sites_dataset
    Site.where(Sequel.|({id: owner.id}, {parent_site_id: owner.id})).order(:parent_site_id.desc, :username).exclude(is_deleted: true)
  end

  def account_sites
    account_sites_dataset.all
  end

  def other_sites_dataset
    account_sites_dataset.exclude(id: self.id).exclude(is_deleted: true)
  end

  def other_sites
    account_sites_dataset.exclude(id: self.id).all
  end

  def account_sites_events_dataset
    ids = account_sites_dataset.select(:id).all.collect {|s| s.id}
    Event.where(site_id: ids)
  end

  def owner
    parent? ? self : parent
  end

  def owned_by?(site)
    !account_sites_dataset.select(:id).where(id: site.id).first.nil?
  end

  def add_profile_comment(opts)
    DB.transaction {
      profile_comment = super
      actioning_site = Site[id: opts[:actioning_site_id]]

      return if actioning_site.owner == owner

      send_email(
        col: :send_comment_emails,
        subject: "#{actioning_site.username.capitalize} commented on your site",
        body: render_template(
          'email/new_comment.erb',
          actioning_site: actioning_site,
          message: opts[:message],
          profile_comment: profile_comment
        )
      )
    }
  end

  class << self
    def featured(limit=6)
      select(:id, :username, :title, :domain).exclude(featured_at: nil).order(:featured_at.desc).limit(limit)
    end

    def valid_email_unsubscribe_token?(email, token)
      email_unsubscribe_token(email) == token
    end

    def email_unsubscribe_token(email)
      Digest::SHA2.hexdigest email+$config['email_unsubscribe_token']
    end

    def valid_login?(username_or_email, plaintext)
      get_site_from_login(username_or_email, plaintext) ? true : false
    end

    def get_site_from_login(username_or_email, plaintext)
      site = get_with_identifier username_or_email
      return nil if site.nil? || site.is_banned || !site.valid_password?(plaintext)
      site
    end

    def bcrypt_cost
      @bcrypt_cost
    end

    def bcrypt_cost=(cost)
      @bcrypt_cost = cost
    end

    def get_with_identifier(username_or_email)
      if username_or_email =~ /@/
        site = get_with_email username_or_email
      else
        site = self[username: username_or_email.downcase]
      end
      return nil if site.nil? || site.is_banned || site.owner.is_banned
      site
    end

    def get_recovery_sites_with_email(email)
      self.where('lower(email) = ?', email.downcase).all
    end

    def get_with_email(email)
      query = self.where(parent_site_id: nil)
      query.where(email: email).first || query.where('lower(email) = ?', email.downcase).first
    end

    def ip_create_limit?(ip)
      Site.where('created_at > ?', Date.today.to_time).where(ip: ip).count > IP_CREATE_LIMIT ||
      Site.where(ip: ip).count > TOTAL_IP_CREATE_LIMIT
    end

    def banned_ip?(ip)
      return false if ENV['RACK_ENV'] == 'production' && ip == '127.0.0.1'
      return false if ip.blank?
      return true if Site.where(is_banned: true).
        where(ip: ip).
        where(['banned_at > ?', Time.now-BANNED_TIME]).
        first

      return true if BlockedIp[ip]

      false
    end

    def ssl_sites
      select(:id, :username, :domain, :ssl_key, :ssl_cert).
      exclude(domain: nil).
      exclude(ssl_key: nil).
      exclude(ssl_cert: nil).
      all
    end
  end

  def is_following?(site)
    followings_dataset.select(:follows__id).filter(site_id: site.id).first ? true : false
  end

  def account_sites_follow?(site)
    account_site_ids = account_sites_dataset.select(:id).all.collect {|s| s.id}
    return true if Follow.where(actioning_site_id: account_site_ids, site_id: site.id).count > 0
    return false
  end

  def scorable_follow?(site)
    return false if site.id == self.id # Do not count follow of yourself
    return false if site.owned_by?(self) # Do not count follow of your own sites
    return false if account_sites_follow?(site) # Do not count follow if any of your other sites follow
    true
  end

  def scorable_follow_count
    score_follow_count = 0

    follows_dataset.all.each do |follow|
      score_follow_count += 1 if scorable_follow?(follow.actioning_site)
    end
    score_follow_count
  end

  def toggle_follow(site)
    return false if followings_dataset.count > MAX_FOLLOWS
    if is_following? site
      DB.transaction do
        follow = followings_dataset.filter(site_id: site.id).first
        return false if follow.nil?
        site.events_dataset.filter(follow_id: follow.id).delete
        follow.delete
        # FIXME This is a being abused somehow. A weekly script now computes this.
        # DB['update sites set follow_count=follow_count-1 where id=?', site.id].first if scorable_follow?(site)
      end
      false
    else
      DB.transaction do
        follow = add_following site_id: site.id
        # FIXME see above.
        # DB['update sites set follow_count=follow_count+1 where id=?', site.id].first if scorable_follow?(site)
        Event.create site_id: site.id, actioning_site_id: self.id, follow_id: follow.id
      end

      true
    end
  end

  def username=(val)
    @redis_proxy_change = true
    @old_username = self.username
    super val.downcase
  end

  def unseen_notifications_dataset
    events_dataset.where(notification_seen: false).exclude(actioning_site_id: self.id)
  end

  def unseen_notifications_count
    @unseen_notifications_count ||= unseen_notifications_dataset.count
  end

  def valid_password?(plaintext)
    is_valid_password = BCrypt::Password.new(owner.values[:password]) == plaintext

    unless is_valid_password
      return false if values[:password].nil?
      is_valid_password = BCrypt::Password.new(values[:password]) == plaintext
    end

    is_valid_password
  end

  def password=(plaintext)
    @password_length = plaintext.nil? ? 0 : plaintext.length
    @password_plaintext = plaintext
    super BCrypt::Password.create plaintext, cost: (self.class.bcrypt_cost || BCrypt::Engine::DEFAULT_COST)
  end

  def new_tags_string=(tags_string)
    @new_tags_string = tags_string
  end

  def save(validate={})
    DB.transaction do
      is_new = new?
      result = super(validate)
      install_new_files if is_new
      result
    end
  end

  def install_new_files
    FileUtils.mkdir_p files_path

    files = []

    %w{index not_found}.each do |name|
      tmpfile = Tempfile.new "newinstall-#{name}"
      tmpfile.write render_template("#{name}.erb")
      tmpfile.close
      files << {filename: "#{name}.html", tempfile: tmpfile}
    end

    tmpfile = Tempfile.new 'style.css'
    tmpfile.close
    FileUtils.cp template_file_path('style.css'), tmpfile.path
    files << {filename: 'style.css', tempfile: tmpfile}

    tmpfile = Tempfile.new 'neocities.png'
    tmpfile.close
    FileUtils.cp template_file_path('neocities.png'), tmpfile.path
    files << {filename: 'neocities.png', tempfile: tmpfile}

    store_files files, new_install: true
  end

  def get_file(path)
    File.read current_files_path(path)
  end

  def before_destroy
    DB.transaction {
      self.domain = nil
      self.save_changes validate: false
      owner.end_supporter_membership! if parent?
      FileUtils.mkdir_p File.join(DELETED_SITES_ROOT, sharding_dir)

      begin
        FileUtils.mv files_path, deleted_files_path
      rescue Errno::ENOENT => e
        # Must have been removed already?
      end

      remove_all_tags
      #remove_all_events
      #Event.where(actioning_site_id: id).destroy
    }
  end

  def after_destroy
    update_redis_proxy_record
    purge_all_cache
  end

  def undelete!
    return false unless Dir.exist? deleted_files_path
    FileUtils.mkdir_p File.join(SITE_FILES_ROOT, sharding_dir)

    DB.transaction {
      FileUtils.mv deleted_files_path, files_path
      self.is_deleted = false
      save_changes
    }

    update_redis_proxy_record
    purge_all_cache
    true
  end

  def unban!
    undelete!
    self.is_banned = false
    self.banned_at = nil
    self.blackbox_whitelisted = true
    save validate: false
  end

  def ban!
    if username.nil? || username.empty?
      raise 'username is missing'
    end

    return if is_banned == true
    self.is_banned = true
    self.banned_at = Time.now
    save validate: false
    destroy
  end

  def ban_all_sites_on_account!
    DB.transaction {
      account_sites.each {|site| site.ban! }
    }
  end

  # Who this site is following
  def followings_dataset
    super.select_all(:follows).inner_join(:sites, :id=>:site_id).exclude(:sites__is_deleted => true).exclude(:sites__is_banned => true).exclude(:sites__profile_enabled => false).order(:score.desc)
  end

  # Who this site follows
  def follows_dataset
    super.select_all(:follows).inner_join(:sites, :id=>:actioning_site_id).exclude(:sites__is_deleted => true).exclude(:sites__is_banned => true).exclude(:sites__profile_enabled => false).order(:score.desc)
  end

  def followings
    followings_dataset.all
  end

  def follows
    follows_dataset.all
  end

  def profile_follows_actioning_ids(limit=nil)
    follows_dataset.select(:actioning_site_id).exclude(:sites__site_changed => false).limit(limit).all
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

  def commenting_allowed?
    return false if owner.commenting_banned == true
    return true if owner.commenting_allowed

    if owner.supporter?
      set commenting_allowed: true
      save_changes validate: false
      return true
    else
      return false if owner.commenting_too_much?
    end

    if (account_sites_events_dataset.exclude(site_change_id: nil).count >= COMMENTING_ALLOWED_UPDATED_COUNT || (created_at < Date.new(2014, 12, 25).to_time && changed_count >= COMMENTING_ALLOWED_UPDATED_COUNT )) &&
       created_at < Time.now - 604800
      owner.set commenting_allowed: true
      owner.save_changes validate: false
      return true
    end

    false
  end

  def commenting_too_much?
    recent_comments = Comment.where(actioning_site_id: owner.id).where{created_at > 24.hours.ago}.count
    recent_profile_comments = owner.profile_commentings_dataset.where{created_at > 24.hours.ago}.count

    return true if (recent_comments + recent_profile_comments) > MAX_COMMENTS_PER_DAY
    false
  end

  def is_a_jerk?
    blocks_dataset_count = blocks_dataset.count
    blocks_dataset_count >= BLOCK_JERK_THRESHOLD && ((blocks_dataset_count / follows_dataset.count.to_f) * 100) > BLOCK_JERK_PERCENTAGE
  end

  def blocking_site_ids
    @blocking_site_ids ||= blockings_dataset.select(:site_id).all.collect {|s| s.site_id}
  end

  def unfollow_blocked_sites!
    blockings.each do |blocking|
      follows.each do |follow|
        follow.destroy if follow.actioning_site_id == blocking.site_id
      end

      followings.each do |following|
        following.destroy if following.site_id == blocking.site_id
      end
    end
  end

  def block!(site)
    block = blockings_dataset.filter(site_id: site.id).first
    return true if block
    add_blocking site: site
    unfollow_blocked_sites!
  end

  def unblock!(site)
    block = blockings_dataset.filter(site_id: site.id).first
    return true if block.nil?
    block.destroy
  end

  def is_blocking?(site)
    @blockings ||= blockings
    !@blockings.select {|b| b.site_id == site.id}.empty?
  end

  def self.valid_username?(username)
    !username.empty? && username.match(/^[a-zA-Z0-9][a-zA-Z0-9_\-]+[a-zA-Z0-9]$/i)
  end

  def self.disposable_email_domains
    File.readlines(DISPOSABLE_EMAIL_BLACKLIST_PATH).collect {|d| d.strip}
  end

  def self.banned_email_domains
    File.readlines(BANNED_EMAIL_BLACKLIST_PATH).collect {|d| d.strip}
  end

  def self.disposable_mx_record?(email)
    email_domain = email.match(/@(.+)/).captures.first

    begin
      email_mx = Resolv::DNS.new.getresource(email_domain, Resolv::DNS::Resource::IN::MX).exchange.to_s
      email_root_domain = email_mx.match(/\.(.+)$/).captures.first
    rescue => e
      # Guess this is your lucky day.
      return false
    end

    return true if disposable_email_domains.include? email_root_domain
    false
  end

  def self.disposable_email?(email)
    return false unless File.exist?(DISPOSABLE_EMAIL_BLACKLIST_PATH)
    return false if email.blank?

    email.strip!

    disposable_email_domains.each do |disposable_email_domain|
      return true if email.match /@#{disposable_email_domain}$/i
    end

    false
  end

  def self.banned_email?(email)
    return false unless File.exist?(BANNED_EMAIL_BLACKLIST_PATH)
    return false if email.blank?

    email.strip!

    banned_email_domains.each do |banned_email_domain|
      return true if email.match /@*#{banned_email_domain}$/i
    end

    false
  end

  def okay_to_upload?(uploaded_file)
    return true if [:supporter].include?(plan_type.to_sym)
    self.class.valid_file_type?(uploaded_file)
  end

  def self.valid_file_mime_type_and_ext?(mime_type, extname)
    unless (Site::VALID_MIME_TYPES.include?(mime_type) || mime_type =~ /text/ || mime_type =~ /inode\/x-empty/) &&
           Site::VALID_EXTENSIONS.include?(extname.sub(/^./, '').downcase)
      return false
    end
    true
  end

  def self.valid_file_type?(uploaded_file)
    mime_type = Magic.guess_file_mime_type uploaded_file[:tempfile].path
    extname = File.extname uploaded_file[:filename]

    # Possibly needed logic for .dotfiles
    #if extname == ''
    #  extname = uploaded_file[:filename]
    #end

    return false unless valid_file_mime_type_and_ext?(mime_type, extname)

    # clamdscan doesn't work on continuous integration for testing
    return true if ENV['CI'] == 'true'

    File.chmod 0666, uploaded_file[:tempfile].path
    line = Terrapin::CommandLine.new(
      "clamdscan", "-i --remove=no --no-summary --stdout :path",
      expected_outcodes: [0, 1]
    )

    begin
      output = line.run path: uploaded_file[:tempfile].path
    rescue Terrapin::ExitStatusError => e
      puts "WARNING: CLAMAV FAILED #{uploaded_file[:tempfile].path} #{e.message}"
      return true
    end

    return true if output == ''

    threat = output.strip.match(/^.+: (.+) FOUND$/).captures.first

    CLAMAV_THREAT_MATCHES.each do |threat_match|
      return false if threat.match threat_match
    end

    true
  end

  def purge_cache(path)
    relative_path = path.gsub base_files_path, ''

    # We gotta flush the dirname too if it's an index file.
    if relative_path != '' && relative_path.match(/\/$|index\.html?$/i)
      PurgeCacheWorker.perform_async username, relative_path

      purge_file_path = Pathname(relative_path).dirname.to_s
      purge_file_path = '' if purge_file_path == '.'
      purge_file_path += '/' if purge_file_path != '/'

      PurgeCacheWorker.perform_async username, '/?surf=1' if purge_file_path == '/'
      PurgeCacheWorker.perform_async username, purge_file_path
    else
      PurgeCacheWorker.perform_async username, relative_path
    end
  end

  def purge_all_cache
    site_files.each do |site_file|
      purge_cache site_file.path
    end
  end

  def is_directory?(path)
    File.directory? files_path(path)
  end

  def create_directory(path)
    path = scrubbed_path path
    relative_path = files_path path

    if Dir.exist?(relative_path) || File.exist?(relative_path)
      return 'Directory (or file) already exists.'
    end

    path_dirs = path.to_s.split('/').select {|p| ![nil, '.', ''].include?(p) }

    path_site_file = ''

    until path_dirs.empty?
      if path_site_file == ''
        path_site_file += path_dirs.shift
      else
        path_site_file += '/' + path_dirs.shift
      end

      raise ArgumentError, 'directory name cannot be empty' if path_site_file == ''

      site_file = SiteFile.where(site_id: self.id, path: path_site_file).first
      if site_file.nil?
        SiteFile.create(
          site_id: self.id,
          path: path_site_file,
          is_directory: true,
          created_at: Time.now,
          updated_at: Time.now
        )
      end
    end

    FileUtils.mkdir_p relative_path
    true
  end

  def move_files_from(oldusername)
    FileUtils.mkdir_p self.class.sharding_base_path(username)
    FileUtils.mkdir_p self.class.sharding_screenshots_path(username)
    FileUtils.mkdir_p self.class.sharding_thumbnails_path(username)
    FileUtils.mv base_files_path(oldusername), base_files_path
    otp = base_thumbnails_path(oldusername)
    osp = base_screenshots_path(oldusername)
    FileUtils.mv(otp, base_thumbnails_path) if File.exist?(otp)
    FileUtils.mv(osp, base_screenshots_path) if File.exist?(osp)
  end

  def install_new_html_file(path)
    tmpfile = Tempfile.new 'neocities_html_template'
    tmpfile.write render_template('index.erb')
    tmpfile.close
    store_files [{filename: path, tempfile: tmpfile}]
    purge_cache path
    tmpfile.unlink
  end

  def file_exists?(path)
    File.exist? files_path(path)
  end

  def after_save
    update_redis_proxy_record if @redis_proxy_change
    save_tags
    super
  end

  def save_tags
    if @new_filtered_tags
      @new_filtered_tags.each do |new_tag_string|
        add_tag_name new_tag_string
      end
      @new_filtered_tags = []
      @new_tags_string = nil
    end
  end

  def add_tag_name(name)
    add_tag Tag[name: name] || Tag.create(name: name)
  end

  def before_create
    self.email_confirmation_token = SecureRandom.hex 3
    super
  end

  def email=(email)
    @original_email = values[:email] unless new?
    super(email.nil? ? nil : email.downcase)
  end

  def can_email?(col=nil)
    return false unless owner.send_emails
    return false if col && !owner.send(col)
    true
  end

  def send_email(args={})
    %i{subject body}.each do |a|
      raise ArgumentError, "argument missing: #{a}" if args[a].nil?
    end

    if email && can_email?(args[:col])
      EmailWorker.perform_async({
        from: FROM_EMAIL,
        to: owner.email,
        subject: args[:subject],
        body: args[:body]
      })
    end
  end

  def parent?
    parent_site_id.nil?
  end

  def ssl_installed?
    !domain.blank? && !ssl_key.blank? && !ssl_cert.blank?
  end

  def sandboxed?
    plan_type == 'free' && created_at > SANDBOX_TIME.ago
  end

  def update_redis_proxy_record
    u_key = "u-#{username}"

    if supporter?
      $redis_proxy.hset u_key, 'is_supporter', '1'
    else
      $redis_proxy.hdel u_key, 'is_supporter'
    end

    if sandboxed?
      $redis_proxy.hset u_key, 'is_sandboxed', '1'
    else
      $redis_proxy.hdel u_key, 'is_sandboxed'
    end

    if values[:domain]
      d_root_key = "d-#{values[:domain]}"
      d_www_key  = "d-www.#{values[:domain]}"

      $redis_proxy.hset u_key, 'domain', values[:domain]
      $redis_proxy.hset d_root_key, 'username', username
      $redis_proxy.hset d_www_key, 'username', username

      if ssl_installed?
        $redis_proxy.hset d_root_key, 'ssl_cert', ssl_cert
        $redis_proxy.hset d_root_key, 'ssl_key',  ssl_key
        $redis_proxy.hset d_www_key,  'ssl_cert', ssl_cert
        $redis_proxy.hset d_www_key,  'ssl_key',  ssl_key
      end

      if is_deleted
        $redis_proxy.del d_root_key
        $redis_proxy.del d_www_key
      end
    else
      $redis_proxy.hdel u_key, 'domain'
    end

    $redis_proxy.del "u-#{@old_username}" if @old_username
    $redis_proxy.del "d-#{@old_domain}" if @old_domain
    $redis_proxy.del "d-www.#{@old_domain}" if @old_domain

    if is_deleted
      $redis_proxy.del u_key
    end

    true
  end

  def ssl_key=(val)
    @redis_proxy_change = true
    super val
  end

  def ssl_cert=(val)
    @redis_proxy_change = true
    super val
  end

  def domain=(domain)
    @old_domain = values[:domain] unless values[:domain].blank?
    @redis_proxy_change = true
    super SimpleIDN.to_ascii(domain)
  end

  def domain
    SimpleIDN.to_unicode values[:domain]
  end

  def validate
    super

    if !self.class.valid_username?(values[:username])
      errors.add :username, 'Usernames can only contain letters, numbers, and hyphens, and cannot start or end with a hyphen.'
    end

    if !values[:username].blank?
      # TODO regex fails for usernames <= 2 chars, tempfix for now.
      if new? && values[:username].nil? || (values[:username].length > 2 && !values[:username].match(VALID_HOSTNAME))
        errors.add :username, 'A valid user/site name is required.'
      end

      if values[:username].length > MAX_USERNAME_LENGTH
        errors.add :username, "User/site name cannot exceed #{MAX_USERNAME_LENGTH} characters."
      end
    end

    # Check that email has been provided
    if parent? && values[:email].empty?
      errors.add :email, 'An email address is required.'
    end

    if parent? && values[:email] =~ /@neocities.org/
      errors.add :email, 'Cannot use this email address.'
    end

    if parent? && (values[:created_at].nil? || values[:created_at] > 1.week.ago) && self.class.disposable_email?(values[:email])
      errors.add :email, 'Cannot use a disposable email address.'
    end

    if parent? && (values[:created_at].nil? || values[:created_at] > 1.week.ago) && self.class.banned_email?(values[:email])
      errors.add :email, 'Registration from this domain is banned due to abuse.'
    end

    # Check for existing email if new or changing email.
    if new? || @original_email
      email_check = self.class.select(:id).filter('lower(email)=?', values[:email])
      email_check = email_check.exclude(id: self.id) unless new?
      email_check = email_check.first

      if parent? && email_check && email_check.id != self.id
        errors.add :email, 'This email address already exists on Neocities.'
      end
    end

    if parent? && (values[:email] =~ EMAIL_SANITY_REGEX).nil?
      errors.add :email, 'A valid email address is required.'
    end

    if !values[:tipping_paypal].blank? && (values[:tipping_paypal] =~ EMAIL_SANITY_REGEX).nil?
      errors.add :tipping_paypal, 'A valid PayPal tipping email address is required.'
    end

    if !values[:tipping_bitcoin].blank? && !AdequateCryptoAddress.valid?(values[:tipping_bitcoin], 'BTC')
      errors.add :tipping_bitcoin, 'Bitcoin tipping address is not valid.'
    end

    # Check for existing user
    user = self.class.select(:id, :username).filter(username: values[:username]).first

    if user
      if user.id != values[:id]
        errors.add :username, 'This username is already taken. Try using another one.'
      end
    end

    if parent? && (values[:password].nil? || (@password_length && @password_length < MINIMUM_PASSWORD_LENGTH))
      errors.add :password, "Password must be at least #{MINIMUM_PASSWORD_LENGTH} characters."
    end

    if !values[:domain].nil? && !values[:domain].empty?
      if values[:domain] =~ /neocities\.org/ || values[:domain] =~ /neocitiesops\.net/
        errors.add :domain, "Domain is already being used.. by Neocities."
      end

      site = Site[domain: values[:domain]]
      if !site.nil? && site.id != self.id
        errors.add :domain, "Domain provided is already being used by another site, please choose another."
      end

      if new? && !parent? && account_sites_dataset.count >= CHILD_SITES_MAX
        errors.add :child_site_id, "For spam prevention reasons, we've capped site creation to #{CHILD_SITES_MAX} sites. Please contact Neocities support to raise your site limit."
      end
    end

    if @new_tags_string
      new_tags = @new_tags_string.split ','
      new_tags.compact!
      @new_filtered_tags = []

      if values[:is_education] == true
        if new?
          if @new_tags_string.nil? || @new_tags_string.empty?
            errors.add :new_tags_string, 'A Class Tag is required.'
          end

          if new_tags.length > 1
            errors.add :new_tags_string, 'Must only have one tag'
          end
        end
      end

      if ((new? ? 0 : tags_dataset.count) + new_tags.length > MAXIMUM_TAGS)
        errors.add :new_tags_string, "Cannot have more than #{MAXIMUM_TAGS} tags for your site."
      end

      new_tags.each do |tag|
        tag.strip!
        if tag.match(/[^a-zA-Z0-9 ]/)
          errors.add :new_tags_string, "Tag \"#{tag}\" can only contain letters (A-Z) and numbers (0-9)."
          break
        end

        if tag.length > Tag::NAME_LENGTH_MAX
          errors.add :new_tags_string, "Tag \"#{tag}\" cannot be longer than #{Tag::NAME_LENGTH_MAX} characters."
          break
        end

        if tag.match(/  /)
          errors.add :new_tags_string, "Tag \"#{tag}\" cannot have spaces."
          break
        end

        if tag.split(' ').length > Tag::NAME_WORDS_MAX
          errors.add :new_tags_string, "Tag \"#{tag}\" cannot be more than #{Tag::NAME_WORDS_MAX} word."
          break
        end

        next if !new? && tags.collect {|t| t.name}.include?(tag)

        @new_filtered_tags << tag
        @new_filtered_tags.uniq!
      end
    end
  end

  def render_template(name, locals={})
    Tilt.new(template_file_path(name), pretty: true).render self, locals
  end

  def template_file_path(name)
    File.join TEMPLATE_ROOT, name
  end

  def current_base_files_path(name=username)
    raise 'username missing' if name.nil? || name.empty?
    return base_deleted_files_path if is_deleted
    base_files_path name
  end

  def base_files_path(name=username)
    raise 'username missing' if name.nil? || name.empty?
    File.join SITE_FILES_ROOT, self.class.sharding_dir(name), name
  end

  def base_deleted_files_path(name=username)
    raise 'username missing' if name.nil? || name.empty?
    File.join DELETED_SITES_ROOT, self.class.sharding_dir(name), name
  end

  def self.sharding_base_path(name)
    File.join SITE_FILES_ROOT, sharding_dir(name)
  end

  def self.sharding_screenshots_path(name)
    File.join SCREENSHOTS_ROOT, sharding_dir(name)
  end

  def self.sharding_thumbnails_path(name)
    File.join THUMBNAILS_ROOT, sharding_dir(name)
  end

  def self.sharding_dir(name)
    chksum = Zlib::crc32(name).to_s
    File.join(chksum[0..1], chksum[2..3])
  end

  def sharding_dir
    self.class.sharding_dir values[:username]
  end

  # https://practicingruby.com/articles/implementing-an-http-file-server?u=dc2ab0f9bb
  def scrubbed_path(path='')
    path ||= ''
    clean = []

    parts = path.to_s.split '/'

    parts.each do |part|
      next if part.empty? || part == '.'
      clean << part if part != '..'
    end

    clean_path = clean.join '/'

    # Scrub carriage garbage (everything below 32 bytes.. http://www.asciitable.com/)
    clean_path.each_codepoint do |c|
      raise ArgumentError, 'invalid character for filename' if c < 32
    end

    clean_path
  end

  def current_files_path(path='')
    File.join current_base_files_path, scrubbed_path(path)
  end

  def files_path(path='')
    File.join base_files_path, scrubbed_path(path)
  end

  def deleted_files_path(path='')
    File.join base_deleted_files_path, scrubbed_path(path)
  end

  def file_list(path='')
    list = Dir.glob(File.join(files_path(path), '*')).collect do |file_path|
      extname = File.extname file_path
      file = {
        path: file_path.gsub(base_files_path+'/', ''),
        name: File.basename(file_path),
        ext: extname.gsub('.', ''),
        is_directory: File.directory?(file_path),
        is_root_index: file_path == "#{base_files_path}/index.html"
      }

      site_file = site_files_dataset.where(path: file_path.gsub(base_files_path, '').sub(/^\//, '')).first

      if site_file
        file[:size] = site_file.size unless file[:is_directory]
        file[:updated_at] = site_file.updated_at
      end

      file[:is_html] = !(extname.match(HTML_REGEX)).nil?
      file[:is_image] = !(file[:ext].match IMAGE_REGEX).nil?
      file[:is_editable] = !(file[:ext].match EDITABLE_FILE_EXT).nil?

      file
    end

    list.select {|f| f[:is_directory]}.sort_by {|f| f[:name]} +
    list.select {|f| f[:is_directory] == false}.sort_by{|f| f[:name].downcase}
  end

  def file_size_too_large?(size)
    return true if size > MAX_FILE_SIZE || size + space_used > maximum_space
    false
  end

  def actual_space_used
    space = 0

    files = Dir.glob File.join(files_path, '**', '*')

    files.each do |file|
      next if File.directory? file
      space += File.size file
    end

    space
  end

  def total_space_used
    total = 0
    account_sites.each {|s| total += s.space_used}
    total
  end

  def remaining_space
    remaining = maximum_space - total_space_used
    remaining < 0 ? 0 : remaining
  end

  def maximum_space
    plan_space = PLAN_FEATURES[(parent? ? self : parent).plan_type.to_sym][:space].to_i

    return custom_max_space if custom_max_space > plan_space

    plan_space
  end

  def space_percentage_used
    ((total_space_used.to_f / maximum_space) * 100).round(1)
  end

  # Note: Change Stat#prune! and the nginx map compiler if you change this business logic.
  def supporter?
    owner.plan_type != 'free'
  end

  def ended_supporter?
    owner.values[:plan_ended]
  end

  def plan_name
    PLAN_FEATURES[plan_type.to_sym][:name]
  end

  def stripe_paying_supporter?
    owner.stripe_customer_id && owner.stripe_subscription_id && !owner.plan_ended && owner.values[:plan_type] && owner.values[:plan_type].match(/free|special/).nil?
  end

  def paypal_paying_supporter?
    owner.paypal_active && owner.paypal_profile_id
  end

  def paying_supporter?
    return true if stripe_paying_supporter? || owner.values[:paypal_active] == true
  end

  def end_supporter_membership!
    owner.end_supporter_membership! unless parent?

    if stripe_paying_supporter?
      customer = Stripe::Customer.retrieve stripe_customer_id
      subscription = customer.subscriptions.retrieve stripe_subscription_id
      subscription.delete

      self.plan_type = nil
      self.stripe_subscription_id = nil
      self.plan_ended = true
    elsif paypal_paying_supporter?
      ppr = PayPal::Recurring.new profile_id: paypal_profile_id
      ppr.cancel

      self.plan_type = nil
      self.paypal_active = false
      self.paypal_profile_id = nil
      self.paypal_token = nil
      self.plan_ended = true
    else
      return false
    end

    save_changes validate: false
    true
  end

  def unconverted_legacy_supporter?
    stripe_customer_id && !plan_ended && values[:plan_type].nil? && stripe_subscription_id.nil?
  end

  def legacy_supporter?
    return false if values[:plan_type].nil?
    !values[:plan_type].match(/plan_/).nil?
  end

  # Note: Change Stat#prune! and the nginx map compiler if you change this business logic.
  def plan_type
    return 'supporter' if owner.values[:paypal_active] == true
    return 'free' if owner.values[:plan_type].nil?
    return 'supporter' if owner.values[:plan_type].match /^plan_/
    return 'supporter' if owner.values[:plan_type] == 'special'
    owner.values[:plan_type]
  end

  def plan_type=(val)
    @redis_proxy_change = true
    super val
  end

  def latest_events(current_page=1, limit=10)
    site_id = self.id
    Event.news_feed_default_dataset.where{Sequel.|({site_id: site_id}, {actioning_site_id: site_id})}.
    order(:created_at.desc).
    paginate(current_page, limit)
  end

  def news_feed(current_page=1, limit=10)
    following_ids = self.followings_dataset.select(:site_id).all.collect {|f| f.site_id}
    search_ids = following_ids+[self.id]

    Event.news_feed_default_dataset.where{Sequel.|({site_id: search_ids}, {actioning_site_id: search_ids})}.
    order(:created_at.desc).
    paginate(current_page, limit)
  end

  def newest_follows
    follows_dataset.where(:follows__created_at => (1.month.ago..Time.now)).order(:follows__created_at.desc).all
  end

  def host
    !domain.empty? ? domain : "#{username}.neocities.org"
  end

  def default_schema
    # Switch-over for when SSL defaulting is ready
    'https'
  end

  def uri
    "#{default_schema}://#{host}"
  end

  def file_uri(path)
    path = '/' + path unless path[0] == '/'
    uri + (path =~ ROOT_INDEX_HTML_REGEX ? '/' : path)
  end

  def title
    begin
      if values[:title].blank? || values[:title].strip.empty?
        !domain.nil? && !domain.empty? ? domain : host
      else
        values[:title]
      end
    rescue
      host
    end
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

  def self.compute_scores
    select(:id, :username, :created_at, :updated_at, :views, :featured_at, :changed_count, :api_calls).exclude(is_banned: true).exclude(is_crashing: true).exclude(is_nsfw: true).exclude(updated_at: nil).where(site_changed: true).all.each do |s|
      s.score = s.compute_score
      s.save_changes validate: false
    end
  end

  SCORE_GRAVITY = 1.8

  def compute_score
    points = 0
    points += (follow_count || 0) * 30
    points += profile_comments_dataset.count * 1
    points += views / 1000
    points += 20 if !featured_at.nil?

    # penalties
    points = 0 if changed_count < 2
    points = 0 if api_calls && api_calls > 1000

    (points / ((Time.now - updated_at) / 7.days)**SCORE_GRAVITY).round(4)
  end

=begin
  def compute_score
    score = 0
    score += (Time.now - created_at) / 1.day
    score -= ((Time.now - updated_at) / 1.day) * 2
    score += 500 if (updated_at > 1.week.ago)
    score -= 1000 if
    score -= 1000 if follow_count == 0
    score += follow_count * 100
    score += profile_comments_dataset.count * 5
    score += profile_commentings_dataset.count
    score.to_i
  end
=end

  def self.browse_dataset
    dataset.select(:id,:username,:hits,:views,:created_at,:plan_type,:parent_site_id,:domain,:score,:title).
      where(is_deleted: false, is_banned: false, is_crashing: false, site_changed: true)
  end

  def suggestions(limit=SUGGESTIONS_LIMIT, offset=0)
    suggestions_dataset = Site.exclude(id: id).exclude(is_deleted: true).exclude(is_nsfw: true).exclude(profile_enabled: false).order(:views.desc, :updated_at.desc)
    suggestions = suggestions_dataset.where(tags: tags).limit(limit, offset).all

    return suggestions if suggestions.length == limit

    ds = self.class.browse_dataset
    ds = ds.select_all :sites
    ds = ds.order :follow_count.desc, :updated_at.desc
    ds = ds.where Sequel.lit("views >= #{SUGGESTIONS_VIEWS_MIN}")
    ds = ds.limit limit - suggestions.length

    suggestions += ds.all
  end

  def screenshot_path(path, resolution)
    File.join base_screenshots_path, "#{path}.#{resolution}.webp"
  end

  def base_screenshots_path(name=username)
    raise 'screenshots name missing' if name.nil? || name.empty?
    File.join self.class.sharding_screenshots_path(name), name
  end

  def base_screenshots_url(name=username)
    raise 'screenshots name missing' if name.nil? || name.empty?
    File.join SCREENSHOTS_URL_ROOT, self.class.sharding_dir(name), name
  end

  def screenshot_exists?(path, resolution)
    File.exist? File.join(base_screenshots_path, "#{path}.#{resolution}.webp")
  end

  def sharing_screenshot_url
    'https://neocities.org'+base_screenshots_url+'/index.html.jpg'
  end

  def screenshot_url(path, resolution)
    path[0] = '' if path[0] == '/'
    out = ''
    out = 'https://neocities.org' if ENV['RACK_ENV'] == 'development'
    out+"#{base_screenshots_url}/#{path}.#{resolution}.webp"
  end

  def base_thumbnails_path(name=username)
    raise 'thumbnails name missing' if name.nil? || name.empty?
    File.join self.class.sharding_thumbnails_path(name), name
  end

  def thumbnail_path(path, resolution)
    File.join base_thumbnails_path, "#{path}.#{resolution}.webp"
  end

  def thumbnail_exists?(path, resolution)
    File.exist? thumbnail_path(path, resolution)
  end

  def thumbnail_delete(path, resolution)
    File.rm thumbnail_path(path, resolution)
  end

  def thumbnail_url(path, resolution)
    path[0] = '' if path[0] == '/'
    "#{THUMBNAILS_URL_ROOT}/#{sharding_dir}/#{values[:username]}/#{path}.#{resolution}.webp"
  end

  def to_rss
    site_change_events = events_dataset.exclude(is_deleted: true).exclude(site_change_id: nil).order(:created_at.desc).limit(10).all

    Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      xml.rss('version' => '2.0') {
        xml.channel {
          xml.title title
          xml.link uri
          xml.description "Site feed for #{title}"
          xml.image {
            xml.url sharing_screenshot_url
            xml.title title
            xml.link uri
          }

          site_change_events.each do |event|
            event_link = "https://neocities.org/site/#{username}?event_id=#{event.id.to_s}"
            xml.item {
              xml.title "#{title} has been updated."
              xml.link event_link
              xml.pubDate event.created_at.rfc822
              xml.guid event_link
            }
          end
        }
      }
    end.to_xml
  end

  def empty_index?
    !site_files_dataset.where(path: ROOT_INDEX_HTML_REGEX).where(sha1_hash: EMPTY_FILE_HASH).first.nil?
  end

  def tipping_enabled?
    tipping_enabled && (!tipping_paypal.blank? || !tipping_bitcoin.blank?)
  end

  def classify(path)
    return nil unless classification_allowed? path
    #$classifier.classify process_for_classification(path)
  end

  def classification_scores(path)
    return nil unless classification_allowed? path
    #$classifier.classification_scores process_for_classification(path)
  end

  def train(path, category='ham')
    return nil unless classification_allowed? path
    # $trainer.train(category, process_for_classification(path))
    site_file = site_files_dataset.where(path: path).first
    site_file.classifier = category
    site_file.save_changes validate: false
  end

  def untrain(path, category='ham')
    return nil unless classification_allowed? path
    # $trainer.untrain(category, process_for_classification(path))
    site_file = site_files_dataset.where(path: path).first
    site_file.classifier = category
    site_file.save_changes validate: false
  end

  def classification_allowed?(path)
    site_file = site_files_dataset.where(path: path).first
    return false if site_file.is_directory
    return false if site_file.size > SiteFile::CLASSIFIER_LIMIT
    return false if !path.match(/\.html$/)
    true
  end

  def process_for_classification(path)
    sanitized = Sanitize.fragment get_file(path)
    sanitized.gsub(/(http|https):\/\//, '').gsub(/[^\w\s]/, '').downcase.split.uniq.select{|v| v.length < SiteFile::CLASSIFIER_WORD_LIMIT}.join(' ')
  end

  # array of hashes: filename, tempfile, opts.
  def store_files(files, opts={})
    results = []
    new_size = 0

    if too_many_files?(files.length)
      results << false
      return results
    end

    files.each do |file|
      existing_size = 0

      site_file = site_files_dataset.where(path: scrubbed_path(file[:filename])).first

      if site_file
        existing_size = site_file.size
      end

      res = store_file(file[:filename], file[:tempfile], file[:opts] || opts)

      if res == true
        new_size -= existing_size
        new_size += file[:tempfile].size
      end

      results << res
    end

    if results.include? true

      DB["update sites set space_used=space_used#{new_size < 0 ? new_size.to_s : '+'+new_size.to_s} where id=?", self.id].first

      if opts[:new_install] != true
        if files.select {|f| f[:filename] =~ /^\/?index.html$/}.length > 0 && site_changed != true && !empty_index?
          DB[:sites].where(id: self.id).update site_changed: true
        end

        time = Time.now

        DB["update sites set site_updated_at=?, updated_at=?, changed_count=changed_count+1 where id=?",
          time,
          time,
          self.id
        ].first
      end

      reload

      #SiteChange.record self, relative_path unless opts[:new_install]
    end

    results
  end

  def delete_file(path)
    return false if files_path(path) == files_path
    path = scrubbed_path path
    site_file = site_files_dataset.where(path: path).first
    site_file.destroy if site_file
    true
  end

  def generate_api_key!
    self.api_key = SecureRandom.hex(16)
    save_changes validate: false
  end

  def sha1_hash_match?(path, sha1_hash)
    relative_path = scrubbed_path path
    site_file = site_files_dataset.where(path: relative_path, sha1_hash: sha1_hash).first
    !site_file.nil?
  end

  def regenerate_thumbnails
    site_files.each do |sf|
      next unless File.extname(sf.path).match IMAGE_REGEX
      ThumbnailWorker.perform_async values[:username], sf.path
    end
  end

  def regenerate_screenshots
    site_files.each do |sf|
      next unless File.extname(sf.path).match HTML_REGEX
      ScreenshotWorker.perform_async values[:username], sf.path
    end
  end

  def regenerate_thumbnails_and_screenshots
    regenerate_screenshots
    regenerate_thumbnails
  end

  def delete_all_thumbnails_and_screenshots
    site_files.each do |sf|
      delete_thumbnail_or_screenshot sf.path
    end
  end

  def delete_thumbnail_or_screenshot(path)
    extname = File.extname path

    if extname.match HTML_REGEX
      screenshots_delete path
    elsif extname.match IMAGE_REGEX
      thumbnails_delete path
    end
  end

  def generate_thumbnail_or_screenshot(path, screenshot_delay=0)
    extname = File.extname path

    if extname.match HTML_REGEX
      ScreenshotWorker.perform_in screenshot_delay.seconds, values[:username], path
    elsif extname.match IMAGE_REGEX
      ThumbnailWorker.perform_async values[:username], path
    end
  end

  def phone_verification_needed?
    return true if phone_verification_required && !phone_verified
    false
  end

  private

  def store_file(path, uploaded, opts={})
    relative_path = scrubbed_path path
    path = files_path path
    pathname = Pathname(path)

    site_file = site_files_dataset.where(path: relative_path).first

    uploaded_sha1 = Digest::SHA1.file(uploaded.path).hexdigest

    if site_file && site_file.sha1_hash == uploaded_sha1
      return false
    end

    if pathname.extname.match(HTML_REGEX) && defined?(BlackBox)
      BlackBoxWorker.perform_in BLACK_BOX_WAIT_TIME, values[:id], relative_path
    end

    relative_path_dir = Pathname(relative_path).dirname
    create_directory relative_path_dir unless relative_path_dir == '.'

    uploaded_size = uploaded.size

    if relative_path == 'index.html'
      begin
        new_title = Nokogiri::HTML(File.read(uploaded.path)).css('title').first.text
      rescue NoMethodError => e
      else
        if new_title.length < TITLE_MAX
          self.title = new_title
          save_changes validate: false
        end
      end
    end

    FileUtils.cp uploaded.path, path
    File.chmod 0640, path

    SiteChange.record self, relative_path if !opts[:new_install] && File.extname(relative_path).match(HTML_REGEX)

    site_file ||= SiteFile.new site_id: self.id, path: relative_path

    site_file.set size: uploaded_size
    site_file.set sha1_hash: uploaded_sha1
    site_file.set updated_at: Time.now
    site_file.save

    purge_cache path
    generate_thumbnail_or_screenshot relative_path, SCREENSHOT_DELAY_SECONDS

    true
  end
end

