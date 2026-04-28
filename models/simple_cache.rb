require 'thread'
require 'time'

module SimpleCache
  MAX_ENTRIES = 256

  @cache = {}
  @semaphore = Mutex.new

  class << self
    def store(name, value, timeout=30)
      @semaphore.synchronize do
        now = Time.now
        prune_expired(now)
        @cache[name] = {value: value, expires_at: now+timeout, stored_at: now}
        prune_oldest
      end
      value
    end

    def get(name)
      @semaphore.synchronize do
        entry = @cache[name]
        return nil if entry.nil?
        if entry[:expires_at] <= Time.now
          @cache.delete(name)
          return nil
        end
        entry[:value]
      end
    end

    def expired?(name)
      @semaphore.synchronize do
        entry = @cache[name]
        return true if entry.nil?
        return false if entry[:expires_at] > Time.now
        @cache.delete(name)
        true
      end
    end

    def clear
      @semaphore.synchronize { @cache.clear }
    end

    def size
      @semaphore.synchronize { @cache.length }
    end

    private

    def prune_expired(now=Time.now)
      @cache.delete_if { |_name, entry| entry[:expires_at] <= now }
    end

    def prune_oldest
      overflow = @cache.length - MAX_ENTRIES
      return if overflow <= 0

      @cache
        .sort_by { |_name, entry| entry[:stored_at] }
        .first(overflow)
        .each { |name, _entry| @cache.delete(name) }
    end
  end
end
