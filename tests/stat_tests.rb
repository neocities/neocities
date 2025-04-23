require_relative './environment.rb'

STAT_LOGS_PATH = 'tests/stat_logs'
STAT_LOGS_DIR_MATCH = "#{STAT_LOGS_PATH}/*.log.gz"

describe 'stats' do
  before do
    Dir[STAT_LOGS_DIR_MATCH].each {|f| FileUtils.rm f}
    @site_one = Fabricate :site
    @site_two = Fabricate :site

    @time = Time.now
    @time_iso8601 = @time.iso8601

    @log = [
      "#{@time_iso8601}\t#{@site_one.username}\t5000\t/\t67.180.75.140\thttp://example.com",
      "#{@time_iso8601}\t#{@site_one.username}\t5000\t/\t67.180.75.140\thttp://example.com",
      "#{@time_iso8601}\t#{@site_one.username}\t5000\t/\t172.56.16.152\thttp://example.com",
      "#{@time_iso8601}\t#{@site_one.username}\t5000\t/\t172.56.16.152\t-",
      "#{@time_iso8601}\t#{@site_two.username}\t5000\t/\t67.180.75.140\thttp://example.com",
      "#{@time_iso8601}\t#{@site_two.username}\t5000\t/\t127.0.0.1\t-",
      "#{@time_iso8601}\t#{@site_two.username}\t5000\t/derp.html\t127.0.0.2\thttps://example.com"
    ]

    Zlib::GzipWriter.open("tests/stat_logs/#{SecureRandom.uuid}.log.gz") do |gz|
      gz.write @log.join("\n")
    end
  end

  it 'works with two logfiles' do
    Zlib::GzipWriter.open("tests/stat_logs/#{SecureRandom.uuid}.log.gz") do |gz|
      gz.write @log.join("\n")
    end
    Stat.parse_logfiles STAT_LOGS_PATH
    stat = @site_one.stats.first
    _(stat.hits).must_equal 8
    _(stat.bandwidth).must_equal 40000
    _(stat.views).must_equal 2
  end

  it 'deals with spaces in paths' do
    @site = Fabricate :site

    Zlib::GzipWriter.open("tests/stat_logs/#{SecureRandom.uuid}.log.gz") do |gz|
      gz.write "2015-05-02T21:16:35+00:00\t#{@site.username}\t612917\t/images/derpie space.png\t67.180.75.140\thttp://derp.com\n"
      gz.write "2015-05-02T21:16:35+00:00\t#{@site.username}\t612917\t/images/derpie space.png\t67.180.75.140\thttp://derp.com\n"
    end

    Stat.parse_logfiles STAT_LOGS_PATH

    _(@site.stats.first.bandwidth).must_equal 612917*2
    #_(@site.stat_referrers.first.url).must_equal 'http://derp.com'
    #_(@site.stat_locations.first.city_name).must_equal 'Menlo Park'
  end

  it 'takes accout for log hit time' do
    @site = Fabricate :site

    Zlib::GzipWriter.open("tests/stat_logs/#{SecureRandom.uuid}.log.gz") do |gz|
      gz.write "2015-05-01T21:16:35+00:00\t#{@site.username}\t612917\t/images/derpie space.png\t67.180.75.140\thttp://derp.com\n"
      gz.write "2015-05-02T21:16:35+00:00\t#{@site.username}\t612917\t/images/derpie space.png\t67.180.75.140\thttp://derp.com\n"
    end

    Stat.parse_logfiles STAT_LOGS_PATH

    _(@site.stats.length).must_equal 2

    [Date.new(2015, 5, 2), Date.new(2015, 5, 1)].each do |date|
      stats = @site.stats.select {|stat| stat.created_at == date}
      _(stats.length).must_equal 1
      stat = stats.first
      _(stat.hits).must_equal 1
      _(stat.views).must_equal 1
      _(stat.bandwidth).must_equal 612917
    end

  end

  it 'deals with spaces in referrer' do
    @site = Fabricate :site

    Zlib::GzipWriter.open("tests/stat_logs/#{SecureRandom.uuid}.log.gz") do |gz|
      gz.write "2015-05-02T21:16:35+00:00\t#{@site.username}\t612917\t/images/derpie space.png\t67.180.75.140\thttp://derp.com?q=what the lump\n"
    end

    Stat.parse_logfiles STAT_LOGS_PATH
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

    _(Stat.where(site_id: count_site_ids).count).must_equal expected_stat_count
    Stat.prune!
    _(Stat.where(site_id: count_site_ids).count).must_equal expected_stat_count-1
    _(Stat.where(site_id: @supporter_site.id).count).must_equal expected_stat_count/2
  end

  it 'prunes referrers' do
    stat_referrer_now = @site_one.add_stat_referrer created_at: Date.today, url: 'http://example.com/now'
    stat_referrer = @site_one.add_stat_referrer created_at: (StatReferrer::RETAINMENT_DAYS-1).days.ago, url: 'http://example.com'
    _(StatReferrer[stat_referrer.id]).wont_be_nil
    _(@site_one.stat_referrers_dataset.count).must_equal 2
    StatReferrer.prune!
    _(@site_one.stat_referrers_dataset.count).must_equal 1
    _(StatReferrer[stat_referrer.id]).must_be_nil
  end

  it 'prunes locations' do
    stat_location = @site_one.add_stat_location(
      created_at: (StatLocation::RETAINMENT_DAYS-1).days.ago,
      country_code2: 'US',
      region_name: 'Minnesota',
      city_name: 'Minneapolis'
    )
    _(StatLocation[stat_location.id]).wont_be_nil
    StatLocation.prune!
    _(StatLocation[stat_location.id]).must_be_nil
  end

  it 'prunes paths' do
    stat_path = @site_one.add_stat_path(
      created_at: (StatPath::RETAINMENT_DAYS-1).days.ago,
      name: '/derpie.html'
    )
    _(StatPath[stat_path.id]).wont_be_nil
    StatPath.prune!
    _(StatPath[stat_path.id]).must_be_nil
  end

  it 'parses logfile' do
    DB[:daily_site_stats].delete
    Stat.parse_logfiles STAT_LOGS_PATH

    @site_one.reload
    _(@site_one.hits).must_equal 4
    _(@site_one.views).must_equal 2
    stat = @site_one.stats.first
    _(stat.hits).must_equal 4
    _(stat.views).must_equal 2
    _(stat.bandwidth).must_equal 20_000

    #@site_one.stat_referrers.count).must_equal 1
    #stat_referrer = @site_one.stat_referrers.first
    #stat_referrer.url).must_equal 'http://example.com'
    #stat_referrer.created_at).must_equal @time.to_date
    #stat_referrer.views).must_equal 2

    #@site_one.stat_paths.length).must_equal 1
    #stat_path = @site_one.stat_paths.first
    #stat_path.name).must_equal '/'
    #stat_path.views).must_equal 4

    #@site_one.stat_locations.length).must_equal 2
    #stat_location = @site_one.stat_locations.first
    #stat_location.country_code2).must_equal 'US'
    #stat_location.region_name).must_equal 'CA'
    #stat_location.city_name).must_equal 'Menlo Park'
    #stat_location.views).must_equal 1

    @site_two.reload
    _(@site_two.hits).must_equal 3
    _(@site_two.views).must_equal 3
    stat = @site_two.stats.first
    _(stat.hits).must_equal 3
    _(stat.views).must_equal 3
    _(stat.bandwidth).must_equal 15_000
    #@site_two.stat_referrers.count).must_equal 2
    #stat_referrer = @site_two.stat_referrers.first
    #stat_referrer.url).must_equal 'http://example.com'
    #stat_referrer.views).must_equal 2

    #stat_paths = @site_two.stat_paths
    #stat_paths.length).must_equal 2
    #stat_paths.first.name).must_equal '/'
    #stat_paths.last.name).must_equal '/derp.html'

    # [geoip.city('67.180.75.140'), geoip.city('172.56.16.152')]

    # Saves to daily_site_stats

    _(DailySiteStat.count).must_equal 1
    d = DailySiteStat.first
    _(d.created_at).must_equal Date.new(@time.year, @time.month, @time.day)
    _(d.hits).must_equal 7
    _(d.views).must_equal 5
    _(d.bandwidth).must_equal 35000
  end
end
