require 'sidekiq/api'
require 'redis-namespace'

class ArchiveWorker
  include Sidekiq::Worker
  sidekiq_options queue: :archive, retry: 2, backtrace: true

  def perform(site_id)
    site = Site[site_id]
    return if site.nil? || site.is_banned? || site.is_deleted

    if site.site_files_dataset.count > 1000
      logger.info 'skipping #{site_id} (#{site.username}) due to > 1000 files'
      return
    end

    queue = Sidekiq::Queue.new self.class.sidekiq_options_hash['queue']
    logger.info "JOB ID: #{jid} #{site_id.inspect}"
    queue.each do |job|
      if job.args == [site_id] && job.jid != jid
        logger.info "DELETING #{job.jid} #{job.args.inspect}"
        job.delete
      end
    end

    site.archive!
  end
end
