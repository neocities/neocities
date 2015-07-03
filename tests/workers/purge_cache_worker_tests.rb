require_relative '../environment.rb'

describe PurgeCacheWorker do
  before do
    @test_ip = '10.0.0.1'
  end

  it 'throws exception without 200 or 404 http status' do
    stub_request(:get, "http://#{@test_ip}/:cache/purgetest.jpg").
      with(headers: {'Host' => 'kyledrake.neocities.org'})
      .to_return(status: 503)

    worker = PurgeCacheWorker.new

    proc {
      worker.perform @test_ip, 'kyledrake', 'test.jpg'
    }.must_raise RestClient::ServiceUnavailable
  end

  it 'handles 404 without exception' do
    stub_request(:get, "http://#{@test_ip}/:cache/purgetest.jpg").
      with(headers: {'Host' => 'kyledrake.neocities.org'})
      .to_return(status: 404)

    worker = PurgeCacheWorker.new
    worker.perform @test_ip, 'kyledrake', 'test.jpg'
  end

  it 'sends a purge request' do
    stub_request(:get, "http://#{@test_ip}/:cache/purgetest.jpg").
      with(headers: {'Host' => 'kyledrake.neocities.org'})
      .to_return(status: 200)

    worker = PurgeCacheWorker.new
    worker.perform @test_ip, 'kyledrake', 'test.jpg'

    assert_requested :get, "http://#{@test_ip}/:cache/purgetest.jpg"
  end
end
