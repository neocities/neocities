get '/activity' do
  @page = params[:page].to_i
  @page = 1 if @page < 1
  @description = 'See recent activity from Neocities websites.'

  halt 404 if params[:event_id]

  tag = nil
  if params[:tag]
    begin
      tag = Tag.clean_name(params[:tag].to_s)
      if tag.empty? || tag.length > Tag::NAME_LENGTH_MAX || tag.match?(Tag::INVALID_TAG_REGEX) || tag.match?(/\s/)
        params.delete 'tag'
        tag = nil
      else
        params[:tag] = tag
      end
    rescue Encoding::CompatibilityError, ArgumentError
      params.delete 'tag'
    end
  end

  tag_record = nil
  if params[:tag]
    tag_record = Tag.select(:id).where(name: params[:tag]).first
    @description = "See recent activity from Neocities websites tagged #{tag}."

    if tag_record
      query1 = Event
        .join(:sites, id: :site_id)
        .join(:sites_tags, site_id: :id)
        .where(sites_tags__tag_id: tag_record.id)
        .where(events__is_deleted: false, sites__is_deleted: false)
        .where{sites__score > Event::ACTIVITY_TAG_SCORE_LIMIT}
        .where(sites__is_nsfw: false)
        .where(follow_id: nil)
        .select_all(:events)

      query2 = Event
        .join(:sites, id: :actioning_site_id)
        .join(:sites_tags, site_id: :id)
        .where(sites_tags__tag_id: tag_record.id)
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
      ds = Event.where(id: nil).order(Sequel.desc(:created_at))
    end
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

  record_count = nil
  if current_site.nil?
    if params[:tag] && tag_record.nil?
      record_count = 0
    else
      cache_key = if params[:tag]
        ['activity_public_tag_record_count', params[:tag]]
      else
        :activity_public_record_count
      end

      if SimpleCache.expired?(cache_key)
        record_count = SimpleCache.store(cache_key, ds.count, 10.minutes)
      else
        record_count = SimpleCache.get(cache_key)
      end
    end

    max_record_count = Event::GLOBAL_PAGINATION_LENGTH * 100
    record_count = [record_count, max_record_count].min
    max_page = (record_count / Event::GLOBAL_PAGINATION_LENGTH.to_f).ceil
    max_page = 1 if max_page < 1
    halt 404 if @page > max_page
  end

  @pagination_dataset = ds.paginate(@page, Event::GLOBAL_PAGINATION_LENGTH, record_count)
  @events = @pagination_dataset.all

  erb :'activity'
end
