require_relative '../environment.rb'

describe PurgeCacheWorker do
  before do
    @test_ips = ['10.0.0.1', '10.0.0.2']
  end

  it 'throws exception without 200 or 404 http status' do
    @test_ips.each do |ip|
      stub_request(:get, "https://#{ip}/:cache/purgetest.jpg").
        with(headers: {'Host' => 'kyledrake.neocities.org'})
        .to_return(status: 503)
    end

    worker = PurgeCacheWorker.new

    proc {
      worker.perform 'kyledrake', 'test.jpg'
    }.must_raise RestClient::ServiceUnavailable
  end

  it 'handles 404 without exception' do
    @test_ips.each do |ip|
      stub_request(:get, "https://#{ip}/:cache/purgetest.jpg").
        with(headers: {'Host' => 'kyledrake.neocities.org'})
        .to_return(status: 404)
    end

    worker = PurgeCacheWorker.new
    worker.perform 'kyledrake', 'test.jpg'
  end

  it 'sends a purge to each dns ip' do
    @test_ips.each do |ip|
      stub_request(:get, "https://#{ip}/:cache/purgetest.jpg").
        with(headers: {'Host' => 'kyledrake.neocities.org'})
        .to_return(status: 200)
    end

    worker = PurgeCacheWorker.new
    worker.perform 'kyledrake', 'test.jpg'

    @test_ips.each do |ip|
      assert_requested :get, "https://#{ip}/:cache/purgetest.jpg"
    end
  end
end
