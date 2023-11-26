class StopForumSpamWorker
  include Sidekiq::Worker
  sidekiq_options queue: :stop_forum_spam, retry: 1, backtrace: true

  def perform(opts)
    txn = Minfraud::Components::Report::Transaction.new(
      ip_address:      opts[:ip],
      tag:             :spam_or_abuse,
      # The following key/values are not mandatory but are encouraged
      maxmind_id:      $config['minfraud_account_id'],
      #minfraud_id:     '01c25cb0-f067-4e02-8ed0-a094c580f5e4',
      #transaction_id:  'txn123'
      #chargeback_code: 'BL'
      notes:           opts[:classifier]
    )

    reporter = Minfraud::Report.new transaction: txn
    res = reporter.report_transaction
    puts res.inspect

    res = HTTP.post 'https://stopforumspam.com/add', form: {
      api_key: $config['stop_forum_spam_api_key'],
      username: opts[:username],
      email: opts[:email],
      ip: opts[:ip]
    }
    puts res.inspect
  end
end
