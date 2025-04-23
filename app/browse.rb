get '/browse/?' do
  @page = params[:page]
  @page = 1 if @page.not_an_integer?

  if params[:tag]
    params[:tag] = params[:tag].gsub(Tag::INVALID_TAG_REGEX, '').gsub(/\s+/, '').slice(0, Tag::NAME_LENGTH_MAX)
    @title = "Sites tagged #{params[:tag]}"
  end

  if is_education?
    ds = education_sites_dataset
  else
    ds = browse_sites_dataset
  end

  ds = ds.paginate @page.to_i, Site::BROWSE_PAGINATION_LENGTH
  @pagination_dataset = ds
  @sites = ds.all

  site_ids = @sites.collect {|s| s[:id]}
  tags = DB['select site_id,name from tags join sites_tags on tags.id=sites_tags.tag_id where site_id IN ?', site_ids].all

  @site_tags = {}
  site_ids.each do |site_id|
    @site_tags[site_id] = tags.select {|t| t[:site_id] == site_id}.collect {|t| t[:name]}
  end

  erb :browse
end

def education_sites_dataset
  ds = Site.filter is_deleted: false
  ds = ds.association_join(:tags).select_all(:sites)
  params[:tag] = current_site.tags.first.name
  ds = ds.where ['tags.name = ?', params[:tag]]
end

def browse_sites_dataset
  ds = Site.browse_dataset
  ds = ds.where is_education: false

  if current_site
    ds = ds.or sites__id: current_site.id

    if !current_site.blocking_site_ids.empty?
      ds = ds.where(Sequel.~(Sequel.qualify(:sites, :id) => current_site.blocking_site_ids))
    end

    if current_site.blocks_dataset.count
      ds = ds.where(
        Sequel.~(Sequel.qualify(:sites, :id) => current_site.blocks_dataset.select(:actioning_site_id).all.collect {|s| s.actioning_site_id})
      )
    end
  end

  if current_site && current_site.is_admin && params[:sites]
    ds = ds.where sites__username: params[:sites].split(',')
    return ds
  end

  params[:sort_by] ||= 'special_sauce'

  case params[:sort_by]
    when 'special_sauce'
      ds = ds.where{score > 1} unless params[:tag]
      ds = ds.order :score.desc, :follow_count.desc, :views.desc, :site_updated_at.desc
    when 'random'
      ds = ds.where{score > 3} unless params[:tag]
      ds = ds.order(Sequel.lit('RANDOM()'))
    when 'most_followed'
      ds = ds.where{views > Site::BROWSE_MINIMUM_FOLLOWER_VIEWS}
      ds = ds.where{follow_count > Site::BROWSE_FOLLOWER_MINIMUM_FOLLOWS}
      ds = ds.where{updated_at > Site::BROWSE_FOLLOWER_UPDATED_AT_CUTOFF.ago} unless params[:tag]
      ds = ds.order :follow_count.desc, :score.desc, :updated_at.desc
    when 'last_updated'
      ds = ds.where{score > 3} unless params[:tag]
      ds = ds.exclude site_updated_at: nil
      ds = ds.order :site_updated_at.desc
    when 'newest'
      ds = ds.where{views > Site::BROWSE_MINIMUM_VIEWS} unless is_admin?
      ds = ds.exclude site_updated_at: nil
      ds = ds.order :created_at.desc, :views.desc
    when 'oldest'
      ds = ds.where{score > 0.4} unless params[:tag]
      ds = ds.exclude site_updated_at: nil
      ds = ds.order(:created_at, :views.desc)
    when 'hits'
      ds = ds.where{score > 1}
      ds = ds.order(:hits.desc, :site_updated_at.desc)
    when 'views'
      ds = ds.where{score > 3}
      ds = ds.order(:views.desc, :site_updated_at.desc)
    when 'featured'
      ds = ds.exclude featured_at: nil
      ds = ds.order :featured_at.desc
    when 'tipping_enabled'
      ds = ds.where tipping_enabled: true
      ds = ds.where("(tipping_paypal is not null and tipping_paypal != '') or (tipping_bitcoin is not null and tipping_bitcoin != '')")
      ds = ds.where{score > 1} unless params[:tag]
      ds = ds.group :sites__id
      ds = ds.order :follow_count.desc, :views.desc, :updated_at.desc
    when 'blocks'
      require_admin
      ds = ds.select{[sites.*, Sequel[count(site_id)].as(:total)]}
      ds = ds.inner_join :blocks, :site_id => :id
      ds = ds.group :sites__id
      ds = ds.order :total.desc
  end

  ds = ds.where ['sites.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]

  if params[:tag]
    ds = ds.select_all :sites
    ds = ds.inner_join :sites_tags, :site_id => :id
    ds = ds.inner_join :tags, :id => :sites_tags__tag_id
    ds = ds.where ['tags.name = ?', params[:tag]]
    ds = ds.where ['tags.is_nsfw = ?', (params[:is_nsfw] == 'true' ? true : false)]
  end

  ds
end

def daily_search_max?
  query_count = $redis_cache.get('search_query_count').to_i
  query_count >= $config['google_custom_search_query_limit']
end

get '/browse/search' do
  @title = 'Site Search'

  @daily_search_max_reached = daily_search_max?

  if @daily_search_max_reached
    params[:q] = nil
  end

  if !params[:q].blank?
    created = $redis_cache.set('search_query_count', 1, nx: true, ex: 86400)
    $redis_cache.incr('search_query_count') unless created

    @start = params[:start].to_i
    @start = 0 if @start < 0

    @resp = JSON.parse HTTP.get('https://www.googleapis.com/customsearch/v1', params: {
      key: $config['google_custom_search_key'],
      cx: $config['google_custom_search_cx'],
      safe: 'active',
      start: @start,
      q: Rack::Utils.escape(params[:q]) + ' -filetype:pdf -filetype:txt site:*.neocities.org'
    })

    @items = []

    if @total_results != 0 && @resp['error'].nil? && @resp['searchInformation']['totalResults'] != "0"
      @total_results = @resp['searchInformation']['totalResults'].to_i
      @resp['items'].each do |item|
        link = Addressable::URI.parse(item['link'])
        unencoded_path = Rack::Utils.unescape(Rack::Utils.unescape(link.path)) # Yes, it needs to be decoded twice
        item['unencoded_link'] = unencoded_path == '/' ? link.host : link.host+unencoded_path
        item['link'] = link

        next if link.host == 'neocities.org'

        username = link.host.split('.').first
        site = Site[username: username]
        next if site.nil? || site.is_deleted || site.is_nsfw

        screenshot_path = unencoded_path

        screenshot_path << 'index' if screenshot_path[-1] == '/'

        ['.html', '.htm'].each do |ext|
          if site.screenshot_exists?(screenshot_path + ext, '540x405')
            screenshot_path += ext
            break
          end
        end

        item['screenshot_url'] = site.screenshot_url(screenshot_path, '540x405')
        @items << item
      end
    end
  else
    @items = nil
    @total_results = 0
  end

  erb :'search'
end