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
    var link = $('#comment_'+commentId+'_delete')

    if (link.hasClass('confirm')) {
      // user confirms deletion, delete
      $.post('/comment/'+commentId+'/delete', {csrf_token: csrfToken}, function(res) {
          location.reload()
      })
    } else {
      // first time user pressed delete, ask if they're sure
      var parentEl = link.parent()

      var spanEl = $('<span>Sure? </span>')

      link.addClass('confirm').text('Delete').detach()
      spanEl.append(link)

      spanEl.append($('<a>Cancel</a>').on('click', function(evnt) {
        var pEl = $(evnt.target.parentElement)
        var el = pEl.children('a.confirm').removeClass('confirm').text('Delete').detach()
        var ppEl = pEl.parent()
        pEl.remove()
        ppEl.append(el)
      }))

      parentEl.append(spanEl)
    }
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
