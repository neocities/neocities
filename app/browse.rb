get '/browse/?' do
  @surfmode = false

  @page = params[:page]
  @page = 1 if @page.not_an_integer?

  begin
    params.delete 'tag' if params[:tag].nil? || !params[:tag].is_a?(String) || params[:tag].strip.empty? || params[:tag].match?(Tag::INVALID_TAG_REGEX)
  rescue Encoding::CompatibilityError
    params.delete 'tag'
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

  if params[:tag]
    @title = "Sites tagged #{params[:tag]}"
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

  case params[:sort_by]
    when 'special_sauce'
      ds = ds.exclude score: nil
      ds = ds.order :score.desc
    when 'followers'
      ds = ds.order :follow_count.desc, :updated_at.desc
    when 'supporters'
      ds = ds.where sites__id: Site.supporter_ids
      ds = ds.order :follow_count.desc, :views.desc, :site_updated_at.desc
    when 'featured'
      ds = ds.exclude featured_at: nil
      ds = ds.order :featured_at.desc
    when 'hits'
      ds = ds.where{views > Site::BROWSE_MINIMUM_VIEWS}
      ds = ds.order(:hits.desc, :site_updated_at.desc)
    when 'views'
      ds = ds.where{views > Site::BROWSE_MINIMUM_VIEWS}
      ds = ds.order(:views.desc, :site_updated_at.desc)
    when 'newest'
      ds = ds.order(:created_at.desc, :views.desc)
    when 'oldest'
      ds = ds.where{views > Site::BROWSE_MINIMUM_VIEWS}
      ds = ds.order(:created_at, :views.desc)
    when 'random'
      ds = ds.where{views > Site::BROWSE_MINIMUM_VIEWS}
      ds = ds.where 'random() < 0.01'
    when 'last_updated'
      ds = ds.where{views > Site::BROWSE_MINIMUM_VIEWS}
      params[:sort_by] = 'last_updated'
      ds = ds.exclude(site_updated_at: nil)
      ds = ds.order(:site_updated_at.desc, :views.desc)
    when 'tipping_enabled'
      ds = ds.where tipping_enabled: true
      ds = ds.where("(tipping_paypal is not null and tipping_paypal != '') or (tipping_bitcoin is not null and tipping_bitcoin != '')")
      ds = ds.where{views > Site::BROWSE_MINIMUM_FOLLOWER_VIEWS}
      ds = ds.group :sites__id
      ds = ds.order :follow_count.desc, :views.desc, :updated_at.desc
    when 'blocks'
      require_admin
      ds = ds.select{[sites.*, Sequel[count(site_id)].as(:total)]}
      ds = ds.inner_join :blocks, :site_id => :id
      ds = ds.group :sites__id
      ds = ds.order :total.desc
    else
      params[:sort_by] = 'followers'
      ds = ds.where{views > Site::BROWSE_MINIMUM_FOLLOWER_VIEWS}
      ds = ds.order :follow_count.desc, :views.desc, :updated_at.desc
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
