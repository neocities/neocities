require 'rmagick'
require 'timeout'
require 'securerandom'
require 'thread'
require 'open3'

class ScreenshotWorker
  SCREENSHOTS_PATH = Site::SCREENSHOTS_ROOT
  HARD_TIMEOUT = 30.freeze
  PAGE_WAIT_TIME = 5.freeze # 3D/VR sites take a bit to render after loading usually.
  include Sidekiq::Worker
  sidekiq_options queue: :screenshots, retry: 3, backtrace: true

  def perform(username, path)

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

    uri = Addressable::URI.parse $config['screenshots_url']
    api_user, api_password = uri.user, uri.password
    uri = "#{uri.scheme}://#{uri.host}:#{uri.port}" + '?' + Rack::Utils.build_query(
      url: Site.select(:username,:domain).where(username: username).first.uri + path,
      wait_time: PAGE_WAIT_TIME
    )

    img_list = Magick::ImageList.new
    img_list.from_blob HTTP.basic_auth(user: api_user, pass: api_password).get(uri).to_s

    img_list.new_image(img_list.first.columns, img_list.first.rows) { self.background_color = "white" }
    img = img_list.reverse.flatten_images
    img_list.destroy!

    user_screenshots_path = File.join SCREENSHOTS_PATH, Site.sharding_dir(username), username
    screenshot_path = File.join user_screenshots_path, File.dirname(path)

    FileUtils.mkdir_p screenshot_path unless Dir.exists?(screenshot_path)

    Site::SCREENSHOT_RESOLUTIONS.each do |res|
      width, height = res.split('x').collect {|r| r.to_i}

      if width == height
        new_img = img.crop_resized width, height, Magick::NorthGravity
      else
        new_img = img.scale width, height
      end

      full_screenshot_path = File.join(user_screenshots_path, "#{path}.#{res}.jpg")
      tmpfile_path = "/tmp/#{SecureRandom.uuid}.jpg"

      begin
        new_img.write(tmpfile_path) { self.quality = 90 }
        new_img.destroy!
        $image_optim.optimize_image! tmpfile_path
        File.open(full_screenshot_path, 'wb') {|file| file.write File.read(tmpfile_path)}
      ensure
        FileUtils.rm tmpfile_path
      end
    end

    img.destroy!

    GC.start full_mark: true, immediate_sweep: true

    true
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
