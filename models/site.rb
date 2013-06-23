class Site < Sequel::Model
  # We might need to include fonts in here..
  VALID_MIME_TYPES = ['text/plain', 'text/html', 'text/css', 'application/javascript', 'image/png', 'image/jpeg', 'image/gif', 'image/svg+xml']
  VALID_EXTENSIONS = %w{ html htm txt text css js jpg jpeg png gif svg md markdown }
  #USERNAME_SHITLIST = %w{ payment secure login signin www ww web } # I thought they were funny personally, but everybody is freaking out so..
  MAX_SPACE = (5242880*2) # 10MB
  MINIMUM_PASSWORD_LENGTH = 5
  BAD_USERNAME_REGEX = /[^\w-]/i
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

    if new? && (values[:username].nil? || values[:username].empty? || values[:username].match(BAD_USERNAME_REGEX)) # || USERNAME_SHITLIST.include?(values[:username])
      errors.add :username, 'A valid username is required.'
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
  end

  def file_path
    File.join DIR_ROOT, 'public', 'sites', username
  end

  def file_list
    Dir.glob(File.join(file_path, '*')).collect {|p| File.basename(p)}.sort.collect {|sitename| SiteFile.new sitename}
  end

  def total_space
    space = Dir.glob(File.join(file_path, '*')).collect {|p| File.size(p)}.inject {|sum,x| sum += x}
    space.nil? ? 0 : space
  end

  def available_space
    remaining = MAX_SPACE - total_space
    remaining < 0 ? 0 : remaining
  end
end
