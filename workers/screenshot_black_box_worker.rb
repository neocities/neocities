# frozen_string_literal: true
require 'sidekiq/api'

class ScreenshotBlackBoxWorker
  include Sidekiq::Worker
  sidekiq_options queue: :screenshot_black_box, retry: 10, backtrace: true

  def perform(site_id, path)
    site = Site[site_id]
    return true if site.nil? || site.is_deleted

    queue = Sidekiq::Queue.new self.class.sidekiq_options_hash['queue']
    logger.info "JOB ID: #{jid} #{site_id} #{path}"
    queue.each do |job|
      if job.args == [site_id, path] && job.jid != jid
        logger.info "DELETING #{job.jid} for #{site_id} #{path}"
        job.delete
      end
    end

    scheduled_jobs = Sidekiq::ScheduledSet.new.select do |scheduled_job|
       scheduled_job.klass == 'ScreenshotBlackBoxWorker' &&
       scheduled_job.args[0] == site_id &&
       scheduled_job.args[1] == path
    end

    scheduled_jobs.each do |scheduled_job|
      logger.info "DELETING scheduled job #{scheduled_job.jid} for #{site_id} #{path}"
      scheduled_job.delete
    end

    BlackBox.new(site, path).check_screenshot
  end
end
