class EmailWorker
  include Sidekiq::Worker
  sidekiq_options queue: :emails, retry: 10, backtrace: true

  def perform(args={})
    Mail.deliver do
      # TODO this is not doing UTF-8 properly.
      from     args['from']
      reply_to args['reply_to']
      to       args['to']
      subject  args['subject']
      body     args['body']
    end
  end
end
