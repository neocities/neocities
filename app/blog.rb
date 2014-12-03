require 'net/http'
require 'uri'

get '/blog' do
  expires 500, :public, :must_revalidate
  return Net::HTTP.get_response(URI('http://blog.neocities.org')).body
end

get '/blog/:article' do |article|
  expires 500, :public, :must_revalidate
  return Net::HTTP.get_response(URI("http://blog.neocities.org/#{article}.html")).body
end