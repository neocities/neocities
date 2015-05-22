class ArchiveWorker
  include Sidekiq::Worker
  sidekiq_options queue: :archive, retry: 10, backtrace: true

  def perform(site_id)
    Site[site_id].archive!
  end
end
