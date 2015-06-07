require 'sidekiq/api'

class ArchiveWorker
  include Sidekiq::Worker
  sidekiq_options queue: :archive, retry: 2, backtrace: true

  def perform(site_id)
    site = Site[site_id]
    return if site.nil? || site.is_banned?

    queue = Sidekiq::Queue.new self.class.sidekiq_options_hash['queue']

    queue.each do |job|
      job.delete if job.args == [site_id] && job.jid != jid
    end

    site.archive!
  end
end
