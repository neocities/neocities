# frozen_string_literal: true
require_relative '../environment.rb'

describe PurgeCacheWorker do
  before do
    $redis_proxy.del(PurgeCacheWorker::PURGE_STREAM_KEY)
  end

  it 'adds entries to the cache purge stream' do
    worker = PurgeCacheWorker.new
    
    worker.perform('testuser', '/index.html')
    worker.perform('anotheruser', '/style.css')

    # Verify entries were added to the stream
    stream_length = $redis_proxy.xlen(PurgeCacheWorker::PURGE_STREAM_KEY)
    _(stream_length).must_equal 2

    # Verify we can read the entries back
    entries = $redis_proxy.xread(PurgeCacheWorker::PURGE_STREAM_KEY, '0')
    messages = entries[PurgeCacheWorker::PURGE_STREAM_KEY]
    _(messages.length).must_equal 2
    
    first_entry = messages[0][1]
    _(first_entry['u']).must_equal 'testuser'
    _(first_entry['p']).must_equal '/index.html'
    
    second_entry = messages[1][1]
    _(second_entry['u']).must_equal 'anotheruser'
    _(second_entry['p']).must_equal '/style.css'
  end
end
