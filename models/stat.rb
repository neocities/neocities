# frozen_string_literal: true
require 'resolv'
require 'zlib'

class Stat < Sequel::Model
  FREE_RETAINMENT_DAYS = 30

  many_to_one :site
  one_to_many :stat_referrers
  one_to_many :stat_locations
  one_to_many :stat_paths

  class << self
    def prune!
      DB[
        "DELETE FROM stats WHERE created_at < ? AND site_id NOT IN ?",
        (FREE_RETAINMENT_DAYS-1).days.ago.to_date.to_s,
        Site.supporter_ids
      ].first
    end

    def parse_logfiles(path)
      total_site_stats = {}

      cache_control_ips = $config['cache_control_ips']

      site_logs = {}

      Dir["#{path}/*.log.gz"].each do |log_path|
        gzfile = File.open log_path, 'r'
        logfile = Zlib::GzipReader.new gzfile

        begin
          while hit = logfile.gets
            hit_array = hit.strip.split "\t"

            raise ArgumentError, hit.inspect if hit_array.length > 6

            time, username, size, path, ip, referrer = hit_array

            next if cache_control_ips.include?(ip)

            log_time = Time.parse time

            next if !referrer.nil? && referrer.match(/bot/i)

            site_logs[log_time] = {} unless site_logs[log_time]

            site_logs[log_time][username] = {
              hits: 0,
              views: 0,
              bandwidth: 0,
              view_ips: [],
              ips: [],
              referrers: {},
              paths: {}
            } unless site_logs[log_time][username]

            total_site_stats[log_time] = {
              hits: 0,
              views: 0,
              bandwidth: 0
            } unless total_site_stats[log_time]

            site_logs[log_time][username][:hits] += 1
            site_logs[log_time][username][:bandwidth] += size.to_i

            total_site_stats[log_time][:hits] += 1
            total_site_stats[log_time][:bandwidth] += size.to_i

            unless site_logs[log_time][username][:view_ips].include?(ip)
              site_logs[log_time][username][:views] += 1

              total_site_stats[log_time][:views] += 1

              site_logs[log_time][username][:view_ips] << ip

              if referrer != '-' && !referrer.nil?
                site_logs[log_time][username][:referrers][referrer] ||= 0
                site_logs[log_time][username][:referrers][referrer] += 1
              end
            end

            site_logs[log_time][username][:paths][path] ||= 0
            site_logs[log_time][username][:paths][path] += 1
          end

          logfile.close
          FileUtils.rm log_path
        rescue => e
          puts "Log parse exception: #{e.inspect}"
          logfile.close
          FileUtils.mv log_path, log_path.gsub('.log', '.brokenlog')
          next
        end
        #FileUtils.rm log_path
      end

      site_logs.each do |log_time, usernames|
        Site.select(:id, :username).where(username: usernames.keys).all.each do |site|
          usernames[site.username][:id] = site.id
        end

        usernames.each do |username, site_log|
          next unless site_log[:id]

          opts = {site_id: site_log[:id], created_at: log_time.to_date.to_s}
          stat = Stat.select(:id).where(opts).first
          stat = Stat.create opts if stat.nil?

          DB['update sites set hits=hits+?, views=views+? where id=?',
            site_log[:hits],
            site_log[:views],
            site_log[:id]
          ].first

          DB[
            'update stats set hits=hits+?, views=views+?, bandwidth=bandwidth+? where id=?',
            site_log[:hits],
            site_log[:views],
            site_log[:bandwidth],
            stat.id
          ].first
        end
      end

      total_site_stats.each do |time, stats|
        opts = {created_at: time.to_date.to_s}
          stat = DailySiteStat.select(:id).where(opts).first
          stat = DailySiteStat.create opts if stat.nil?

          DB[
            'update daily_site_stats set hits=hits+?, views=views+?, bandwidth=bandwidth+? where created_at=?',
            stats[:hits],
            stats[:views],
            stats[:bandwidth],
            time.to_date
          ].first
      end
    end
  end
end

=begin
require 'io/extra'
require 'geoip'

# Note: This isn't really a class right now.
module Stat


  class << self
    def parse_logfiles(path)
      Dir["#{path}/*.log"].each do |logfile_path|
        parse_logfile logfile_path
        FileUtils.rm logfile_path
      end
    end

    def parse_logfile(path)
      geoip = GeoIP.new GEOCITY_PATH
      logfile = File.open path, 'r'

      hits = []

      while hit = logfile.gets
        time, username, size, path, ip, referrer = hit.split ' '

        site = Site.select(:id).where(username: username).first
        next unless site

        paths_dataset = StatsDB[:paths]
        path_record = paths_dataset[name: path]
        path_id = path_record ? path_record[:id] : paths_dataset.insert(name: path)

        referrers_dataset = StatsDB[:referrers]
        referrer_record = referrers_dataset[name: referrer]
        referrer_id = referrer_record ? referrer_record[:id] : referrers_dataset.insert(name: referrer)

        location_id = nil

        if city = geoip.city(ip)
          locations_dataset = StatsDB[:locations].select(:id)
          location_hash = {country_code2: city.country_code2, region_name: city.region_name, city_name: city.city_name}

          location = locations_dataset.where(location_hash).first
          location_id = location ? location[:id] : locations_dataset.insert(location_hash)
        end

        hits << [site.id, referrer_id, path_id, location_id, size, time]
      end

      StatsDB[:hits].import(
        [:site_id, :referrer_id, :path_id, :location_id, :bytes_sent, :logged_at],
        hits
      )
    end
  end
end




=begin
    def parse_logfile(path)
      hits = {}
      visits = {}
      visit_ips = {}

      logfile = File.open path, 'r'

      while hit = logfile.gets
        time, username, size, path, ip, referrer = hit.split ' '

        hits[username] ||= 0
        hits[username] += 1
        visit_ips[username] = [] if !visit_ips[username]

        unless visit_ips[username].include? ip
          visits[username] ||= 0
          visits[username] += 1
          visit_ips[username] << ip
        end
      end

      logfile.close


      hits.each do |username,hitcount|
        DB['update sites set hits=hits+? where username=?', hitcount, username].first
      end

      visits.each do |username,visitcount|
        DB['update sites set views=views+? where username=?', visitcount, username].first
      end
    end
  end
=end

=begin
  def self.parse(logfile_path)
    hits = {}
    visits = {}
    visit_ips = {}

    logfile = File.open logfile_path, 'r'

    while hit = logfile.gets
      time, username, size, path, ip = hit.split ' '

      hits[username] ||= 0
      hits[username] += 1

      visit_ips[username] = [] if !visit_ips[username]

      unless visit_ips[username].include?(ip)
        visits[username] ||= 0
        visits[username] += 1
        visit_ips[username] << ip
      end
    end

    logfile.close

    hits.each do |username,hitcount|
      DB['update sites set hits=hits+? where username=?', hitcount, username].first
    end

    visits.each do |username,visitcount|
      DB['update sites set views=views+? where username=?', visitcount, username].first
    end
  end
=end
