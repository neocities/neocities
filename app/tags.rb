post '/tags/add' do
  require_login
  current_site.new_tags_string = params[:tags]

  if current_site.valid?
    current_site.save_tags
  else
    flash[:errors] = current_site.errors.first.last.first
  end

  redirect request.referer
end

post '/tags/remove' do
  require_login

  if params[:tags].is_a?(Array)
    DB.transaction {
      params[:tags].each do |tag|
        tag_to_remove = current_site.tags.select {|t| t.name == tag}.first
        current_site.remove_tag(tag_to_remove) if tag_to_remove
      end
    }
  end

  redirect request.referer
end

get '/tags/autocomplete/:name.json' do |name|
  Tag.autocomplete(name).collect {|t| t[:name]}.to_json
end
