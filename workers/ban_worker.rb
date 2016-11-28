class BanWorker
  include Sidekiq::Worker
  sidekiq_options queue: :ban, retry: 10, backtrace: true

  def perform(site_id)
    Site[site_id].ban!
  end
end
