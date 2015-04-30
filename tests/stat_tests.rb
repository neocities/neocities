require_relative './environment.rb'

STAT_LOGS_PATH = 'tests/stat_logs'
STAT_LOGS_DIR_MATCH = "#{STAT_LOGS_PATH}/*.log"

def log(&block)
  File.open("tests/stat_logs/#{SecureRandom.uuid}.log", 'w') do |f|
    yield f
  end
end

def random_time
  (Time.now - rand(5000)).iso8601
end

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

  it 'parses multiple sets of logs' do
    geoip = GeoIP.new Stat::GEOCITY_PATH

    paths = ["/", "/#{SecureRandom.hex}", "/#{SecureRandom.hex}"]
    cities = [geoip.city('67.180.75.140'), geoip.city('172.56.16.152')]
    referrers = ['-', "http://#{@site_one.host}", "https://#{@site_one.host}", "http://insaneclownpossee.com"]
    sites = [@site_one, @site_two]

    test_hits = []

    100.times { |i|
      test_hits.push({
        time: random_time,
        username: sites[rand(sites.length)].username,
        size: rand(5000),
        path: paths[rand(paths.length)],
        ip: i.odd? ? cities.first.ip : cities.last.ip,
        referrer: referrers[rand(referrers.length)]
      })
    }

    log do |f|
      test_hits.each {|h| f.puts "#{h[:time]} #{h[:username]} #{h[:size]} #{h[:path]} #{h[:ip]} #{h[:referrer]}"}
    end

    Stat.parse_logfiles STAT_LOGS_PATH

    Dir["#{STAT_LOGS_PATH}/*.log"].length.must_equal 0

    sites_total = 0
    [@site_one, @site_two].each do |site|
      site.reload
      sites_total += site.hits
      site.views.must_equal 2
    end

    sites_total.must_equal 100

    stats = Stat.where(site_id: [@site_one.id, @site_two.id]).all
    stats.length.must_equal 2

    stats.collect {|stat| stat.hits}.inject{|sum,x| sum + x }.must_equal 100
    stats.collect {|stat| stat.views}.inject{|sum,x| sum + x }.must_equal 4

    sites.each do |site|
      test_hits.select {|h| h[:username] == site.username}.length.must_equal(
        stats.select {|s| s.site.username == site.username}.first.hits
      )
    end
  end
end
