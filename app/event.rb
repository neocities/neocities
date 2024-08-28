post '/event/:event_id/toggle_like' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]
  return 403 if event.site.is_blocking?(current_site)
  return 403 if event.actioning_site.is_blocking?(current_site)
  liked_response = event.toggle_site_like(current_site) ? 'liked' : 'unliked'
  {result: liked_response, event_like_count: event.likes_dataset.count, liking_site_names: event.liking_site_usernames}.to_json
end

post '/event/:event_id/comment' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]

  return 403 if event.actioning_site.is_blocking?(current_site)

  site = event.site

  if(site.is_blocking?(current_site) ||
     site.profile_comments_enabled == false ||
     current_site.commenting_allowed? == false ||
     (current_site.is_a_jerk? && event.site_id != current_site.id && !site.is_following?(current_site)) ||
     params[:message].length > Site::MAX_COMMENT_SIZE)
    return {result: 'error'}.to_json
  end

  event.add_site_comment current_site, params[:message]
  {result: 'success'}.to_json
end

post '/event/:event_id/update_profile_comment' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]
  return {result: 'error'}.to_json unless (current_site.id == event.profile_comment.actioning_site_id &&
                                           params[:message].length <= Site::MAX_COMMENT_SIZE)

  event.profile_comment.update message: params[:message]
  return {result: 'success'}.to_json
end

post '/event/:event_id/delete' do |event_id|
  require_login
  content_type :json

  event = Event[id: event_id]

  if event.site_id == current_site.id || event.actioning_site_id == current_site.id
    event.delete
    return {result: 'success'}.to_json
  end

  return {result: 'error'}.to_json
end
