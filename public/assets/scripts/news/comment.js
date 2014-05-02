var Comment = function(eventId, csrfToken) {
  this.eventId = eventId
  this.csrfToken = csrfToken
}

Comment.prototype.create = function(form) {
  var self = this
  var form = $(form)
  var comment = form.find('[name="comment"]').val()
  form.remove()

  $.post('/event/'+this.eventId+'/comment', {csrf_token: this.csrfToken, message: comment}, function(res) {
    console.log(res)
  })
  
}