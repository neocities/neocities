class Site < Sequel::Model
  MINIMUM_PASSWORD_LENGTH = 5
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
  
  def valid_password?(plaintext)
    BCrypt::Password.new(values[:password]) == plaintext
  end

  def password=(plaintext)
    @password_length = plaintext.nil? ? 0 : plaintext.length
    @password_plaintext = plaintext
    values[:password] = BCrypt::Password.create plaintext, cost: (self.class.bcrypt_cost || BCrypt::Engine::DEFAULT_COST)
  end

  def after_save
    if @new_tag_strings
      @new_tag_strings.each do |new_tag_string|
        add_tag Tag[name: new_tag_string] || Tag.create(name: new_tag_string)
      end
    end
  end

  def after_create
    DB['update servers set slots_available=slots_available-1 where id=?', self.server.id].first
  end

  def new_tags=(tags_string)
    tags_string.gsub! /[^a-zA-Z0-9, ]/, ''
    tags = tags_string.split ','
    tags.collect! {|c| (c.match(/^\w+\s\w+/) || c.match(/^\w+/)).to_s }
    @new_tag_strings = tags
  end

  def before_validation
    self.server ||= Server.with_slots_available
  end

  def validate
    super

    if server.nil?
      errors.add :over_capacity, 'We are currently at capacity, and cannot create your home page. We will fix this shortly. Please come back later and try again, our apologies.'
    end

    if values[:username].nil? || values[:username].empty? || values[:username].match(/[^\w.-]/i)
      errors.add :username, 'A valid username is required.'
    end

    # Check for existing user
    user = self.class.select(:username).filter(username: values[:username]).first
    if !user.nil? && (user.id != values[:id])
      errors.add :username, 'This username is already taken. Try using another one.'
    end

    if values[:password].nil? || (@password_length && @password_length < MINIMUM_PASSWORD_LENGTH)
      errors.add :password, "Password must be at least #{MINIMUM_PASSWORD_LENGTH} characters."
    end
  end
end