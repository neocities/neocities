require 'thread'
require 'time'

module SimpleCache
  @cache = {}
  @semaphore = Mutex.new

  class << self
    def store(name, value, timeout=30)
      @semaphore.synchronize {
        @cache[name] = {value: value, expires_at: Time.now+timeout}
      }
      value
    end

    def get(name)
      @cache[name][:value]
    end

    def expired?(name)
      return false if @cache[name] && @cache[name][:expires_at] > Time.now
      true
    end
  end
end