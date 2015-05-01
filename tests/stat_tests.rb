require_relative './environment.rb'

STAT_LOGS_PATH = 'tests/stat_logs'
STAT_LOGS_DIR_MATCH = "#{STAT_LOGS_PATH}/*.log"

describe 'stats' do
  before do
    Dir[STAT_LOGS_DIR_MATCH].each {|f| FileUtils.rm f}
    @site_one = Fabricate :site
    @site_two = Fabricate :site

    @t = Time.now.iso8601
    @s1u = @site_one.username
    @s2u = @site_two.username
  end

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

    Stat.where(site_id: count_site_ids).count.must_equal expected_stat_count
    Stat.prune!
    Stat.where(site_id: count_site_ids).count.must_equal expected_stat_count-1
    Stat.where(site_id: @supporter_site.id).count.must_equal expected_stat_count/2
  end

  it 'parses logfile' do
    time = Time.now.iso8601
    log = [
      "#{time} #{@site_one.username} 5000 / 67.180.75.140 http://example.com",
      "#{time} #{@site_one.username} 5000 / 67.180.75.140 http://example.com",
      "#{time} #{@site_one.username} 5000 / 172.56.16.152 http://example.com",
      "#{time} #{@site_one.username} 5000 / 172.56.16.152 -",
      "#{time} #{@site_two.username} 5000 / 67.180.75.140 http://example.com",
      "#{time} #{@site_two.username} 5000 / 127.0.0.1 -",
      "#{time} #{@site_two.username} 5000 / 127.0.0.2 https://example.com"
    ]

    File.open("tests/stat_logs/#{SecureRandom.uuid}.log", 'w') do |file|
      file.write log.join("\n")
    end

    Stat.parse_logfiles STAT_LOGS_PATH

    @site_one.reload
    @site_one.hits.must_equal 4
    @site_one.views.must_equal 2
    stat = @site_one.stats.first
    stat.hits.must_equal 4
    stat.views.must_equal 2
    referrer = stat.stat_referrers.first
    referrer.url.must_equal 'http://example.com'
    referrer.views.must_equal 2

    @site_two.reload
    @site_two.hits.must_equal 3
    @site_two.views.must_equal 3
    stat = @site_two.stats.first
    stat.hits.must_equal 3
    stat.views.must_equal 3
    stat.stat_referrers.length.must_equal 2
    referrer = stat.stat_referrers.first
    referrer.url.must_equal 'http://example.com'
    referrer.views.must_equal 2
    referrer = stat.stat_referrers.last
    referrer.url.must_equal 'https://example.com'
    referrer.views.must_equal 1

    # [geoip.city('67.180.75.140'), geoip.city('172.56.16.152')]
  end
end
