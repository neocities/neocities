class Stat < Sequel::Model
  GEOCITY_PATH = './files/GeoLiteCity.dat'
  FREE_RETAINMENT_DAYS = 7

  many_to_one :site
  one_to_many :stat_referrers
  one_to_many :stat_locations
  one_to_many :stat_paths

  class << self
    def prune!
      DB[
        "DELETE FROM stats WHERE created_at < ? AND site_id NOT IN (SELECT id FROM sites WHERE plan_type IS NOT NULL OR plan_type != 'free')",
        (FREE_RETAINMENT_DAYS-1).days.ago.to_date.to_s
      ].first

      binding.pry

    end

    def parse_logfiles(path)
      Dir["#{path}/*.log"].each do |log_path|
        site_logs = {}
        logfile = File.open log_path, 'r'

        while hit = logfile.gets
          time, username, size, path, ip, referrer = hit.split ' '

          next if referrer.match /bot/i

          site_logs[username] = {
            hits: 0,
            views: 0,
            view_ips: [],
            ips: [],
            referrers: {},
            paths: {}
          } unless site_logs[username]

          site_logs[username][:hits] += 1

          unless site_logs[username][:view_ips].include?(ip)
            site_logs[username][:views] += 1
            site_logs[username][:view_ips] << ip

            if referrer != '-'
              site_logs[username][:referrers][referrer] ||= 0
              site_logs[username][:referrers][referrer] += 1
            end
          end

          site_logs[username][:paths][path] ||= 0
          site_logs[username][:paths][path] += 1
        end

        logfile.close

        current_time = Time.now.utc
        current_day_string = current_time.to_date.to_s

        Site.select(:id, :username).where(username: site_logs.keys).all.each do |site|
          site_logs[site.username][:id] = site.id
        end

        DB.transaction do
          site_logs.each do |username, site_log|
            DB['update sites set hits=hits+?, views=views+? where username=?',
               site_log[:hits],
               site_log[:views],
               username
              ].first

            opts = {site_id: site_log[:id], created_at: current_day_string}

            stat = Stat.select(:id).where(opts).first
            DB[:stats].lock('EXCLUSIVE') { stat = Stat.create opts } if stat.nil?

            DB[
              'update stats set hits=hits+?, views=views+? where site_id=?',
              site_log[:hits],
              site_log[:views],
              site_log[:id]
            ].first

            site_log[:referrers].each do |referrer,views|
              opts = {stat_id: stat.id, url: referrer}
              stat_referrer = StatReferrer.select(:id).where(opts).first
              DB[:stat_referrers].lock('EXCLUSIVE') {
                stat_referrer = StatReferrer.create opts
              } if stat_referrer.nil?
              DB['update stat_referrers set views=views+? where stat_id=?', views, stat.id].first
            end
          end
        end

        FileUtils.rm log_path
      end
    end

    def get_or_create
      DB[:stats].lock 'EXCLUSIVE' do
        stat = Stat.where(opts).first
        stat ||= Stat.new opts
        stat.hits += site_log[:hits]
        stat.views += site_log[:views]
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
