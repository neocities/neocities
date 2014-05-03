var Comment = {
  create: function(eventId, csrfToken, form) {
    var form = $(form)
    var comment = form.find('[name="comment"]').val()
    form.remove()

    $.post('/event/'+eventId+'/comment', {csrf_token: csrfToken, message: comment}, function(res) {
      console.log(res)
      location.reload()
    })
  },

  delete: function(commentId, csrfToken) {
    $.post('/comment/'+commentId+'/delete', {csrf_token: csrfToken}, function(res) {
      console.log(res)
      location.reload()
    })
  }
}