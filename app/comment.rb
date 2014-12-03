post '/comment/:comment_id/toggle_like' do |comment_id|
  require_login
  content_type :json
  comment = Comment[id: comment_id]
  liked_response = comment.toggle_site_like(current_site) ? 'liked' : 'unliked'
  {result: liked_response, comment_like_count: comment.comment_likes_dataset.count, liking_site_names: comment.liking_site_usernames}.to_json
end

post '/comment/:comment_id/delete' do |comment_id|
  require_login
  content_type :json
  comment = Comment[id: comment_id]

  if comment.event.site == current_site || comment.actioning_site == current_site
    comment.delete
    return {result: 'success'}.to_json
  end

  return {result: 'error'}.to_json
end