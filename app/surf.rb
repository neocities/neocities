get '/surf/?' do
  not_found # 404 for now
  @page = params[:page]
  @page = 1 if @page.not_an_integer?
  params.delete 'tag' if params[:tag].nil? || params[:tag].strip.empty?
  site_dataset = browse_sites_dataset
  site_dataset = site_dataset.paginate @page.to_i, 1
  @page_count = site_dataset.page_count || 1
  @site = site_dataset.first
  redirect "/browse?#{Rack::Utils.build_query params}" if @site.nil?
    @title = "Surf Mode - #{@site.title}"
  erb :'surf', layout: false
end

get '/surf/:username' do |username|
  not_found # 404 for now
  @site = Site.select(:id, :username, :title, :domain, :views, :stripe_customer_id).where(username: username).first
  not_found if @site.nil?
  @title = @site.title
  not_found if @site.nil?
  erb :'surf', layout: false
end
