get '/tags/autocomplete/:name.json' do |name|
  Tag.autocomplete(name).collect {|t| t[:name]}.to_json
end
