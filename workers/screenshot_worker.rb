require 'securerandom'
require 'open3'

class ScreenshotWorker
  SCREENSHOTS_PATH = Site::SCREENSHOTS_ROOT
  HARD_TIMEOUT = 30.freeze
  PAGE_WAIT_TIME = 5.freeze # 3D/VR sites take a bit to render after loading usually.
  include Sidekiq::Worker
  sidekiq_options queue: :screenshots, retry: 4, backtrace: true

  def perform(username, path)
    site = Site[username: username]
    return if site.nil? || site.is_deleted

    queue = Sidekiq::Queue.new self.class.sidekiq_options_hash['queue']
    logger.info "JOB ID: #{jid} #{username} #{path}"
    queue.each do |job|
      if job.args == [username, path] && job.jid != jid
        logger.info "DELETING #{job.jid} for #{username} #{path}"
        job.delete
      end
    end

    scheduled_jobs = Sidekiq::ScheduledSet.new.select do |scheduled_job|
       scheduled_job.klass == 'ScreenshotWorker' &&
       scheduled_job.args[0] == username &&
       scheduled_job.args[1] == path
    end

    scheduled_jobs.each do |scheduled_job|
      logger.info "DELETING scheduled job #{scheduled_job.jid} for #{username} #{path}"
      scheduled_job.delete
    end

    path = "/#{path}" unless path[0] == '/'

    uri = Addressable::URI.parse $config['screenshot_urls'].sample
    api_user, api_password = uri.user, uri.password
    uri = "#{uri.scheme}://#{uri.host}:#{uri.port}" + '?' + Rack::Utils.build_query(
      url: Site.select(:username,:domain).where(username: username).first.uri + path,
      wait_time: PAGE_WAIT_TIME
    )

    begin
      base_image_tmpfile_path = "/tmp/#{SecureRandom.uuid}.png"

      http_resp = HTTP.basic_auth(user: api_user, pass: api_password).get(uri)
      BlackBox.new(site, path).check_uri(http_resp.headers['X-URL']) if defined?(BlackBox) && http_resp.headers['X-URL']
      File.write base_image_tmpfile_path, http_resp.to_s

      user_screenshots_path = File.join SCREENSHOTS_PATH, Site.sharding_dir(username), username
      screenshot_path = File.join user_screenshots_path, File.dirname(path)
      FileUtils.mkdir_p screenshot_path unless Dir.exist?(screenshot_path)

      # We only need the full PNG for the main index right now
      if path.match /^\/index.html?$/
        ImageOptimizer.new(base_image_tmpfile_path, level: 1).optimize
        FileUtils.cp base_image_tmpfile_path, File.join(user_screenshots_path, "#{path}.png")
      end

      # Optimized image for open graph link expanders
      image = Rszr::Image.load base_image_tmpfile_path
      image.resize! 1200, 630, crop: :n
      image.save File.join(user_screenshots_path, "#{path}.jpg"), quality: 85
      ImageOptimizer.new(File.join(user_screenshots_path, "#{path}.jpg")).optimize

      Site::SCREENSHOT_RESOLUTIONS.each do |res|
        width, height = res.split('x').collect {|r| r.to_i}
        full_screenshot_path = File.join(user_screenshots_path, "#{path}.#{res}.webp")
        opts = {resize_w: width, resize_h: height, near_lossless: 0}

        if width == height
          opts.merge! crop_x: 160, crop_y: 0, crop_w: 960, crop_h: 960
        end

        WebP.encode base_image_tmpfile_path, full_screenshot_path, opts
      end

      true
    rescue WebP::EncoderError => e
      puts "Failed: #{username} #{path} #{e.inspect}"
    rescue => e
      raise e
    ensure
      FileUtils.rm base_image_tmpfile_path if File.exist?(base_image_tmpfile_path)
    end
  end

  sidekiq_retries_exhausted do |msg|
    username, path = msg['args']
    # This breaks too much so we're disabling it.
    #site = Site[username: username]
    #site.is_crashing = true
    #site.save_changes validate: false

=begin
        if site.email
          EmailWorker.perform_async({
            from: 'web@neocities.org',
            to: site.email,
            subject: "[NeoCities] The web page \"#{path}\" on your site (#{username}.neocities.org) is slow",
            body: "Hi there! This is an automated email to inform you that we're having issues loading your site to take a "+
                  "screenshot. It is possible that this is an error specific to our screenshot program, but it is much more "+
                  "likely that your site is too slow to be used with browsers. We don't want Neocities sites crashing browsers, "+
                  "so we're taking steps to inform you and see if you can resolve the issue. "+
                  "We may have to de-list your web site from being viewable in our browse page if it is not resolved shortly. "+
                  "We will review the site manually before taking this step, so don't worry if your site is fine and we made "+
                  "a mistake."+
                  "\n\nOur best,\n- Neocities"
          })
        end
=end
  end
end
