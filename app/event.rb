post '/event/:event_id/toggle_like' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]
  return 403 if event.site && event.site.is_blocking?(current_site)
  return 403 if event.actioning_site && event.actioning_site.is_blocking?(current_site)
  liked_response = event.toggle_site_like(current_site) ? 'liked' : 'unliked'
  {result: liked_response, event_like_count: event.likes_dataset.count, liking_site_names: event.liking_site_usernames}.to_json
end

post '/event/:event_id/comment' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]

  if event.site && event.site.is_blocking?(current_site)
    flash[:error] = comment_unavailable_message(event.site)
    return {result: 'error', message: flash[:error]}.to_json
  end

  if event.actioning_site && event.actioning_site.is_blocking?(current_site)
    flash[:error] = comment_unavailable_message(event.actioning_site)
    return {result: 'error', message: flash[:error]}.to_json
  end

  site = event.site
  message = normalize_comment_message(params[:message])
  message_error = comment_message_error(message)
  unavailable_message = comment_unavailable_message(site)

  if(site.is_blocking?(current_site) ||
     site.profile_comments_enabled == false ||
     current_site.commenting_allowed? == false ||
     (current_site.is_a_jerk? && event.site_id != current_site.id && !site.is_following?(current_site)) ||
     message_error)
    flash[:error] = message_error || unavailable_message
    return {result: 'error', message: flash[:error]}.to_json
  end

  event.add_site_comment current_site, message
  {result: 'success'}.to_json
end

post '/event/:event_id/update_profile_comment' do |event_id|
  require_login
  content_type :json
  event = Event[id: event_id]
  message = normalize_comment_message(params[:message])
  message_error = comment_message_error(message)
  return {result: 'error'}.to_json unless (current_site.id == event.profile_comment.actioning_site_id &&
                                           message_error.nil?)

  event.profile_comment.update message: message
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
