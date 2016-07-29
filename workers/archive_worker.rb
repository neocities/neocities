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
        logger.info "DELETING #{job.jid} for site_id #{site_id}"
        job.delete
      end
    end

    scheduled_jobs = Sidekiq::ScheduledSet.new.select do |scheduled_job|
       scheduled_job.klass == 'ArchiveWorker' &&
       scheduled_job.args[0] == site_id
    end

    scheduled_jobs.each do |scheduled_job|
      logger.info "DELETING scheduled job #{scheduled_job.jid} for site_id #{site_id}"
      scheduled_job.delete
    end

    site.archive!
  end
end
