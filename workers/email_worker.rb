class EmailWorker
  include Sidekiq::Worker

  def perform(args={})
    Mail.deliver do
       to      args[:to]
       subject args[:subject]
       body    args[:body]
    end
  end
end
