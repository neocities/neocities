var Comment = {
  create: function(eventId, csrfToken, form) {
    var form = $(form)
    var comment = form.find('[name="comment"]').val()
    form.remove()
    $.post('/event/'+eventId+'/comment', {csrf_token: csrfToken, message: comment}, function(res) {
      location.reload()
    })
  },

  delete: function(commentId, csrfToken) {
    $.post('/comment/'+commentId+'/delete', {csrf_token: csrfToken}, function(res) {
      location.reload()
    })
  },

  toggleLike: function(commentId, csrfToken) {
    var link = $('#comment_'+commentId+'_like')

    $.post('/comment/'+commentId+'/toggle_like', {csrf_token: csrfToken}, function(res) {
      if(res.result == 'liked')
        link.text('Unlike ('+res.comment_like_count+')')

      if(res.result == 'unliked') {
        var linkText = 'Like'

        if(res.comment_like_count > 0)
          linkText += ' ('+res.comment_like_count+')'

        link.text(linkText)
      }
      link.attr('data-original-title', res.liking_site_names.join('<br>'))
    })
  }
}
