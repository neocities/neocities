require_relative '../environment.rb'

describe DeleteCacheWorker do
  before do
    @test_ip = '10.0.0.1'
  end

  it 'handles 404 without exception' do
    stub_request(:get, "http://#{@test_ip}/:cache/purge/test.jpg").
      with(headers: {'Host' => 'kyledrake.neocities.org'})
      .to_return(status: 404)

    worker = DeleteCacheWorker.new
    worker.perform @test_ip, 'kyledrake', '/test.jpg'
  end

  it 'sends a purge request' do
    stub_request(:get, "http://#{@test_ip}/:cache/purge/test.jpg").
      with(headers: {'Host' => 'kyledrake.neocities.org'})
      .to_return(status: 200)

    worker = DeleteCacheWorker.new
    worker.perform @test_ip, 'kyledrake', '/test.jpg'

    assert_requested :get, "http://#{@test_ip}/:cache/purge/test.jpg"
  end

  it 'handles spaces correctly' do
    stub_request(:get, "http://#{@test_ip}/:cache/purge/te st.jpg").
      with(headers: {'Host' => 'kyledrake.neocities.org'})
      .to_return(status: 200)

    url = Addressable::URI.encode_component(
      "http://#{@test_ip}/:cache/purge/te st.jpg",
      Addressable::URI::CharacterClasses::QUERY
    )

    worker = DeleteCacheWorker.new
    worker.perform @test_ip, 'kyledrake', '/te st.jpg'

    assert_requested :get, url
  end

  it 'works without forward slash' do
    stub_request(:get, "http://#{@test_ip}/:cache/purge/test.jpg").
      with(headers: {'Host' => 'kyledrake.neocities.org'})
      .to_return(status: 200)

    worker = DeleteCacheWorker.new
    worker.perform @test_ip, 'kyledrake', 'test.jpg'
  end
end
