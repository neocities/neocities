var Event = {
  delete: function(eventId, csrfToken) {
    var link = $('#event_'+eventId+'_actions a.event_delete')

    if (link.hasClass('confirm')) {
      // user confirms deletion, delete
      $.post('/event/'+eventId+'/delete', {csrf_token: csrfToken}, function(res) {
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
  }
}
