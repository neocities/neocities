class EmailWorker
  include Sidekiq::Worker
  sidekiq_options queue: :emails, retry: 10, backtrace: true

  def perform(args={})
    raise 'no' if ENV['RACK_ENV'].nil? || ENV['RACK_ENV'] == 'development'
    unsubscribe_token = Site.email_unsubscribe_token args['to']

    if args['no_footer']
      footer = ''
    else
      footer = "\n\n---\nYou are receiving this email because you have a Neocities site. If you would like to subscribe from Neocities emails, just visit this url:\nhttps://neocities.org/settings/unsubscribe_email?email=#{Rack::Utils.escape args['to']}&token=#{unsubscribe_token}"
    end

    Mail.deliver do
      # TODO this is not doing UTF-8 properly.
      from     args['from']
      reply_to args['reply_to']
      to       args['to']
      subject  args['subject']
      body     args['body']+footer
    end
  end
end
