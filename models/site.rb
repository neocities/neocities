class Site < Sequel::Model
  MINIMUM_PASSWORD_LENGTH = 5
  
  unrestrict_primary_key
  many_to_one :server
  
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

  def validate
    super

    if values[:username].nil? || values[:username].empty?
      errors.add :username, 'valid username is required'
    end

    # Check for existing user
    user = self.class.select(:username).filter(username: values[:username]).first
    if !user.nil? && (user.id != values[:id])
      errors.add :username, 'this username is already taken'
    end

    if values[:password].nil? || (@password_length && @password_length < MINIMUM_PASSWORD_LENGTH)
      errors.add :password, "password must be at least #{MINIMUM_PASSWORD_LENGTH} characters" 
    end
  end
end