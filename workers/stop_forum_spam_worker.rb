class StopForumSpamWorker
  include Sidekiq::Worker
  sidekiq_options queue: :stop_forum_spam, retry: 1, backtrace: true

  def perform(opts)
    opts.merge! api_key: $config['stop_forum_spam_api_key']
    res = HTTP.post 'https://stopforumspam.com/add', opts
    puts res.inspect
  end
end
