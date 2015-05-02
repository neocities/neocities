require_relative './environment.rb'

STAT_LOGS_PATH = 'tests/stat_logs'
STAT_LOGS_DIR_MATCH = "#{STAT_LOGS_PATH}/*.log"

describe 'stats' do
  before do
    Dir[STAT_LOGS_DIR_MATCH].each {|f| FileUtils.rm f}
    @site_one = Fabricate :site
    @site_two = Fabricate :site

    @time = Time.now
    @time_iso8601 = @time.iso8601

    log = [
      "#{@time_iso8601} #{@site_one.username} 5000 / 67.180.75.140 http://example.com",
      "#{@time_iso8601} #{@site_one.username} 5000 / 67.180.75.140 http://example.com",
      "#{@time_iso8601} #{@site_one.username} 5000 / 172.56.16.152 http://example.com",
      "#{@time_iso8601} #{@site_one.username} 5000 / 172.56.16.152 -",
      "#{@time_iso8601} #{@site_two.username} 5000 / 67.180.75.140 http://example.com",
      "#{@time_iso8601} #{@site_two.username} 5000 / 127.0.0.1 -",
      "#{@time_iso8601} #{@site_two.username} 5000 /derp.html 127.0.0.2 https://example.com"
    ]

    File.open("tests/stat_logs/#{SecureRandom.uuid}.log", 'w') do |file|
      file.write log.join("\n")
    end
  end
=begin
  it 'prunes logs for free sites' do
    @free_site = Fabricate :site
    @supporter_site = Fabricate :site, plan_type: 'supporter'

    day = Date.today
    (Stat::FREE_RETAINMENT_DAYS+1).times do |i|
      [@free_site, @supporter_site].each do |site|
        Stat.create site_id: site.id, created_at: day
      end
      day = day - 1
    end

    count_site_ids = [@free_site.id, @supporter_site.id]
    expected_stat_count = (Stat::FREE_RETAINMENT_DAYS+1)*2

    [@free_site, @supporter_site].each do |site|
      site.stats.last.add_stat_referrer url: 'https://example.com'
    end

    Stat.where(site_id: count_site_ids).count.must_equal expected_stat_count
    Stat.prune!
    Stat.where(site_id: count_site_ids).count.must_equal expected_stat_count-1
    Stat.where(site_id: @supporter_site.id).count.must_equal expected_stat_count/2

    @free_site.stats.last.stat_referrers.length.must_equal 0
    @supporter_site.stats.last.stat_referrers.length.must_equal 1
  end
=end
  it 'parses logfile' do
    Stat.parse_logfiles STAT_LOGS_PATH

    @site_one.reload
    @site_one.hits.must_equal 4
    @site_one.views.must_equal 2
    stat = @site_one.stats.first
    stat.hits.must_equal 4
    stat.views.must_equal 2
    stat.bandwidth.must_equal 20_000
    @site_one.stat_referrers.count.must_equal 1
    stat_referrer = @site_one.stat_referrers.first
    stat_referrer.url.must_equal 'http://example.com'
    stat_referrer.created_at.must_equal @time.to_date
    stat_referrer.views.must_equal 2

    @site_one.stat_paths.length.must_equal 1
    stat_path = @site_one.stat_paths.first
    stat_path.name.must_equal '/'
    stat_path.views.must_equal 4

    @site_one.stat_locations.length.must_equal 2
    stat_location = @site_one.stat_locations.first
    stat_location.country_code2.must_equal 'US'
    stat_location.region_name.must_equal 'CA'
    stat_location.city_name.must_equal 'Menlo Park'
    stat_location.views.must_equal 1

    @site_two.reload
    @site_two.hits.must_equal 3
    @site_two.views.must_equal 3
    stat = @site_two.stats.first
    stat.hits.must_equal 3
    stat.views.must_equal 3
    stat.bandwidth.must_equal 15_000
    @site_two.stat_referrers.count.must_equal 2
    stat_referrer = @site_two.stat_referrers.first
    stat_referrer.url.must_equal 'http://example.com'
    stat_referrer.views.must_equal 2

    stat_paths = @site_two.stat_paths
    stat_paths.length.must_equal 2
    stat_paths.first.name.must_equal '/'
    stat_paths.last.name.must_equal '/derp.html'

    # [geoip.city('67.180.75.140'), geoip.city('172.56.16.152')]
  end
end
