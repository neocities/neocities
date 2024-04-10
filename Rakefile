require 'rake/testtask'

task :environment do
  require './environment.rb'
end

desc "Run all tests"
Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList['tests/**/*_tests.rb']
  t.verbose = false
  t.warning = false
end

task :default => :test

desc "prune logs"
task :prune_logs => [:environment] do
  Stat.prune!
  StatLocation.prune!
  StatReferrer.prune!
  StatPath.prune!
end

desc "parse logs"
task :parse_logs => [:environment] do
  Stat.parse_logfiles $config['logs_path']
end

desc 'Update disposable email blacklist'
task :update_disposable_email_blacklist => [:environment] do
  # Formerly: https://raw.githubusercontent.com/martenson/disposable-email-domains/master/disposable_email_blocklist.conf
  uri = URI.parse('https://raw.githubusercontent.com/disposable/disposable-email-domains/master/domains.txt')
  File.write(Site::DISPOSABLE_EMAIL_BLACKLIST_PATH, HTTP.get(uri))
end

desc 'Update banned IPs list'
task :update_blocked_ips => [:environment] do

  filename = 'listed_ip_365_ipv46'
  zip_path = "/tmp/#{filename}.zip"

  File.open(zip_path, 'wb') do |file|
    response = HTTP.get "https://www.stopforumspam.com/downloads/#{filename}.zip"
    response.body.each do |chunk|
      file.write chunk
    end
  end

  Zip::File.open(zip_path) do |zip_file|
    zip_file.each do |entry|
      if entry.name == "#{filename}.txt"
        ips = entry.get_input_stream.read
        insert_hashes = []
        ips.each_line { |ip| insert_hashes << { ip: ip.strip, created_at: Time.now } }
        ips = nil

        # Database transaction
        DB.transaction do
          DB[:blocked_ips].delete
          DB[:blocked_ips].multi_insert insert_hashes
        end
      end
    end
  end

  FileUtils.rm zip_path
end

desc 'rebuild_thumbnails'
task :rebuild_thumbnails => [:environment] do
  dirs = Dir[Site::SITE_FILES_ROOT+'/**/*'].collect {|s| s.sub(Site::SITE_FILES_ROOT, '')}.collect {|s| s.sub('/', '')}
  dirs.each do |d|
    next if File.directory?(d)

    full_path = d.split('/')

    username = full_path.first
    path = '/'+full_path[1..full_path.length].join('/')

    if Pathname(path).extname.gsub('.', '').match Site::IMAGE_REGEX
      begin
        ThumbnailWorker.new.perform username, path
      rescue Magick::ImageMagickError
      end
    end
  end
end

desc 'compute_scores'
task :compute_scores => [:environment] do
  Site.compute_scores
end

desc 'renew_ssl_certs'
task :renew_ssl_certs => [:environment] do
  delay = 0
  DB[%{select id from sites where (domain is not null or domain != '') and is_banned != 't' and is_deleted != 't' and (cert_updated_at is null or cert_updated_at < ?)}, 60.days.ago].all.each do |site|
    LetsEncryptWorker.perform_in delay.seconds, site[:id]
    delay += 10
  end
end

desc 'purge_tmp_turds'
task :purge_tmp_turds => [:environment] do
  ['neocities_screenshot*', 'RackMultipart*', 'neocities_saving_file*', 'newinstall-*', '*.dmp', 'davfile*', 'magick*', '*.scan', '*.jpg'].each do |target|
    Dir.glob("/tmp/#{target}").select {|filename| File::Stat.new(filename).ctime < (Time.now - 3600)}.each {|filename| FileUtils.rm(filename)}
  end
end

desc 'compute_follow_count_scores'
task :compute_follow_count_scores => [:environment] do

  Site.select(:id,:username,:follow_count).all.each do |site|
    count = site.scorable_follow_count

    if count != 0
      puts "#{site.username} #{site.follow_count} => #{count}"
    end
    DB['update sites set follow_count=? where id=?', count, site.id].first
  end
end

desc 'ml_screenshots_list_dump'
task :ml_screenshots_list_dump => [:environment] do
  ['phishing', 'spam', 'ham', nil].each do |classifier|
    File.open("./files/screenshot-urls#{classifier.nil? ? '' : '-'+classifier.to_s}.txt", 'w') do |fp|
      SiteFile.where(classifier: classifier).where(path: 'index.html').each do |site_file|
        begin
          fp.write "#{site_file.site.screenshot_url('index.html', Site::SCREENSHOT_RESOLUTIONS.first)}\n"
        rescue NoMethodError
        end
      end
    end
  end
end

desc 'generate_sitemap'
task :generate_sitemap => [:environment] do
  sorted_sites = {}

  sites = Site.
    select(:id, :username, :updated_at, :profile_enabled).
    where(site_changed: true).
    exclude(updated_at: nil).
    exclude(is_deleted: true).
    order(:follow_count, :updated_at).
    all

  site_files = []

  sites.each do |site|
    site.site_files_dataset.exclude(path: 'not_found.html').where(path: /\.html?$/).all.each do |site_file|

      if site.file_uri(site_file.path) == site.uri+'/'
        priority = 0.5
      else
        priority = 0.4
      end

      site_files << [site.file_uri(site_file.path), site_file.updated_at.utc.iso8601, priority]
    end
  end

  sites = nil
  GC.start

  sitemap_root = File.join Site::PUBLIC_ROOT, 'sitemap'
  FileUtils.mkdir_p sitemap_root

  index = 0
  until site_files.empty?
    sfs = site_files.pop 50000

    file = File.open File.join(sitemap_root, "sites-#{index}.xml.gz"), 'w'

    Zlib::GzipWriter.open File.join(sitemap_root, "sites-#{index}.xml.gz") do |gz|
      gz.write %{<?xml version="1.0" encoding="UTF-8"?>\n}
      gz.write %{<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n}

      sfs.each do |sf|
        gz.write %{<url><loc>#{sf[0].encode(xml: :text)}</loc><lastmod>#{sf[1].encode(xml: :text)}</lastmod><priority>#{sf[2].to_s.encode(xml: :text)}</priority></url>\n}
      end

      gz.write %{</urlset>}
    end

    index += 1
  end


  # Set basic neocities.org root paths
  builder = Nokogiri::XML::Builder.new { |xml|
    xml.urlset(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') {
      File.read(File.join(DIR_ROOT, 'files', 'root_site_uris.txt')).each_line { |uri|
        priority, changefreq, uri = uri.strip.split(',')
        xml.url {
          xml.loc uri
          xml.changefreq changefreq
          xml.priority priority
        }
      }
    }
  }

  Zlib::GzipWriter.open File.join(sitemap_root, 'root.xml.gz') do |gz|
    gz.write builder.to_xml(encoding: 'UTF-8')
  end


  # Tagged sites sitemap
  builder = Nokogiri::XML::Builder.new { |xml|
    xml.urlset(xmlns: 'http://www.sitemaps.org/schemas/sitemap/0.9') {
      Tag.popular_names(Site.count).each { |tag|
        xml.url {
          xml.loc "https://neocities.org/browse?sort_by=views&tag=#{tag[:name]}"
          xml.changefreq 'daily'
          xml.lastmod Time.now.utc.iso8601
        }
      }
    }
  }

  Zlib::GzipWriter.open File.join(sitemap_root, 'tags.xml.gz') do |gz|
    gz.write builder.to_xml(encoding: 'UTF-8')
  end


  # Final index.xml.gz entrypoint
  Zlib::GzipWriter.open File.join(sitemap_root, 'index.xml.gz') do |gz|
    gz.write %{<?xml version="1.0" encoding="UTF-8"?>\n}
    gz.write %{<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n}
    gz.write %{<sitemap><loc>https://neocities.org/sitemap/root.xml.gz</loc><lastmod>#{Time.now.utc.iso8601}</lastmod></sitemap>\n}
    gz.write %{<sitemap><loc>https://neocities.org/sitemap/tags.xml.gz</loc><lastmod>#{Time.now.utc.iso8601}</lastmod></sitemap>\n}
    0.upto(index-1).each do |i|
      gz.write %{<sitemap><loc>https://neocities.org/sitemap/sites-#{i}.xml.gz</loc><lastmod>#{Time.now.utc.iso8601}</lastmod></sitemap>\n}
    end
    gz.write %{</sitemapindex>}
  end
end
