get '/surf/?' do
  params.delete 'tag' if params[:tag].nil? || params[:tag].empty?
  site_dataset = browse_sites_dataset
  site_dataset = site_dataset.paginate @current_page, 1
  @page_count = site_dataset.page_count || 1
  @site = site_dataset.first
  redirect "/browse?#{Rack::Utils.build_query params}" if @site.nil?
  erb :'surf', layout: false
end

get '/surf/:username' do |username|
  @site = Site.select(:id, :username, :title, :domain, :views, :stripe_customer_id).where(username: username).first
  @title = @site.title
  not_found if @site.nil?
  erb :'surf', layout: false
end