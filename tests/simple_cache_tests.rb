# frozen_string_literal: true
require_relative './environment.rb'

describe SimpleCache do
  before do
    SimpleCache.clear
  end

  after do
    SimpleCache.clear
  end

  it 'removes expired entries when checking expiration' do
    SimpleCache.store(:expired_cache_entry, 'stale', -1)

    _(SimpleCache.expired?(:expired_cache_entry)).must_equal true
    _(SimpleCache.size).must_equal 0
  end

  it 'bounds stored entries' do
    (SimpleCache::MAX_ENTRIES + 10).times do |index|
      SimpleCache.store("cache-key-#{index}", index, 60)
    end

    _(SimpleCache.size).must_equal SimpleCache::MAX_ENTRIES
    _(SimpleCache.get('cache-key-0')).must_be_nil
    _(SimpleCache.get("cache-key-#{SimpleCache::MAX_ENTRIES + 9}")).must_equal SimpleCache::MAX_ENTRIES + 9
  end
end
