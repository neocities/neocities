get '/activity' do
  #expires 7200, :public, :must_revalidate if self.class.production? # 2 hours

  @page = params[:page] || 1

  if params[:tag]
    query1 = Event
      .join(:sites, id: :site_id)
      .join(:sites_tags, site_id: :id)
      .join(:tags, id: :tag_id)
      .where(tags__name: params[:tag])
      .where(events__is_deleted: false, sites__is_deleted: false)
      .where{sites__score > Event::ACTIVITY_TAG_SCORE_LIMIT}
      .where(sites__is_nsfw: false)
      .where(follow_id: nil)
      .select_all(:events)

    query2 = Event
      .join(:sites, id: :actioning_site_id)
      .join(:sites_tags, site_id: :id)
      .join(:tags, id: :tag_id)
      .where(tags__name: params[:tag])
      .where(events__is_deleted: false, sites__is_deleted: false)
      .where{sites__score > Event::ACTIVITY_TAG_SCORE_LIMIT}
      .where(sites__is_nsfw: false)
      .where(follow_id: nil)
      .select_all(:events)

    if current_site
      blocking_site_ids = current_site.blocking_site_ids
      query1 = query1.where(Sequel.|({events__site_id: nil}, ~{events__site_id: blocking_site_ids})).where(Sequel.|({events__actioning_site_id: nil}, ~{events__actioning_site_id: blocking_site_ids}))
      query2 = query2.where(Sequel.|({events__site_id: nil}, ~{events__site_id: blocking_site_ids})).where(Sequel.|({events__actioning_site_id: nil}, ~{events__actioning_site_id: blocking_site_ids}))
    end

    ds = query1.union(query2, all: false).order(Sequel.desc(:created_at))
  else
    ds = Event.news_feed_default_dataset.exclude(sites__is_nsfw: true)

    if current_site
      blocking_site_ids = current_site.blocking_site_ids
      ds = ds.where(Sequel.|({events__site_id: nil}, ~{events__site_id: blocking_site_ids})).where(Sequel.|({events__actioning_site_id: nil}, ~{events__actioning_site_id: blocking_site_ids}))
    end

    ds = ds.where(
      Sequel.expr(Sequel[:sites][:score] > Event::GLOBAL_SCORE_LIMIT) |
      Sequel.expr(Sequel[:actioning_sites][:score] > Event::GLOBAL_SCORE_LIMIT)
    )
  end

  @pagination_dataset = ds.paginate @page.to_i, Event::GLOBAL_PAGINATION_LENGTH
  @events = @pagination_dataset.all

  erb :'activity'
end