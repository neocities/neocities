class BlackBoxWorker
  include Sidekiq::Worker
  sidekiq_options queue: :black_box, retry: 10, backtrace: true

  def perform(site_id, path)
    site = Site[site_id]
    return true if site.nil? || site.is_deleted
    BlackBox.new(site, path).tos_violation_check!
  end
end


# BlackBox.tos_violation_check self, uploaded
