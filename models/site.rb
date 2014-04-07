require 'tilt'

class Site < Sequel::Model
  # We might need to include fonts in here..
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
  MAX_SPACE = (5242880*2) # 10MB
  MINIMUM_PASSWORD_LENGTH = 5
  BAD_USERNAME_REGEX = /[^\w-]/i
  VALID_HOSTNAME = /^[a-z0-9][a-z0-9-]+?[a-z0-9]$/i # http://tools.ietf.org/html/rfc1123

  # FIXME smarter DIR_ROOT discovery
  DIR_ROOT        = './'
  TEMPLATE_ROOT   = File.join DIR_ROOT, 'views', 'templates'
  PUBLIC_ROOT     = File.join DIR_ROOT, 'public'
  SITE_FILES_ROOT = File.join PUBLIC_ROOT, (ENV['RACK_ENV'] == 'test' ? 'sites_test' : 'sites')

  many_to_one :server
  many_to_many :tags

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

  def new_tags=(tags_string)
    tags_string.gsub! /[^a-zA-Z0-9, ]/, ''
    tags = tags_string.split ','
    tags.collect! {|c| (c.match(/^\w+\s\w+/) || c.match(/^\w+/)).to_s }
    @new_tag_strings = tags
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
      File.write file_path("#{name}.html"), render_template("#{name}.slim")
    end
  end

  def get_file(filename)
    File.read file_path(filename)
  end

  def ban!
    DB.transaction {
      FileUtils.mv files_path, File.join(PUBLIC_ROOT, 'banned_sites', username)
      self.is_banned = true

      if !['127.0.0.1', nil, ''].include? ip
        `sudo ufw insert 1 deny from #{ip}`
      end

      save(validate: false)
    }
  end

  def store_file(filename, uploaded)
    FileUtils.mv uploaded.path, file_path(filename)
    File.chmod(0640, file_path(filename))
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
      # File was probably already deleted
    end
  end

  def move_files_from(oldusername)
    FileUtils.mv files_path(oldusername), files_path
  end

  def install_new_html_file(name)
    File.write file_path(name), render_template('index.slim')
  end

  def file_exists?(filename)
    File.exist? file_path(filename)
  end

  def after_save
    if @new_tag_strings
      @new_tag_strings.each do |new_tag_string|
        add_tag Tag[name: new_tag_string] || Tag.create(name: new_tag_string)
      end
    end
    super
  end

  def after_create
    DB['update servers set slots_available=slots_available-1 where id=?', self.server.id].first
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

    # TODO regex fails for usernames <= 2 chars, tempfix for now.
    if new? && values[:username].length > 2 && !values[:username].match(VALID_HOSTNAME)
      errors.add :username, 'A valid user/site name is required.'
    end
    
    if values[:username].length > 32
      errors.add :username, 'User/site name cannot exceed 32 characters.'
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
  end

  def render_template(name)
    Tilt.new(File.join(TEMPLATE_ROOT, name), pretty: true).render self
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

  def total_space
    space = Dir.glob(File.join(files_path, '*')).collect {|p| File.size(p)}.inject {|sum,x| sum += x}
    space.nil? ? 0 : space
  end
  
  def total_space_in_megabytes
    (total_space.to_f / 2**20).round(2)
  end

  def available_space
    remaining = MAX_SPACE - total_space
    remaining < 0 ? 0 : remaining
  end
  
  def available_space_in_megabytes
    (available_space.to_f / 2**20).round(2)
  end
end
