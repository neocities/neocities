class BanWorker
  include Sidekiq::Worker
  sidekiq_options queue: :ban, retry: 10, backtrace: true

  def perform(site_id)
    site = Site[site_id]
    site.ban! unless site.supporter?
  end
end
