var Like = function(eventId, csrfToken) {
  this.eventId = eventId
  this.csrfToken = csrfToken
  this.link = $('#event_'+this.eventId+'_actions a#like')
}

Like.prototype.toggleLike = function() {
  var self = this
  $.post('/event/'+this.eventId+'/toggle_like', {csrf_token: this.csrfToken}, function(res) {
    if(res.result == 'liked')
      self.link.text('Unlike ('+res.event_like_count+')')

    if(res.result == 'unliked') {
      var linkText = 'Like'

      if(res.event_like_count > 0)
        linkText += ' ('+res.event_like_count+')'

      self.link.text(linkText)
    }
  })
}