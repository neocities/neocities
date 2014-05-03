var Event = {
  delete: function(eventId, csrfToken) {
    $.post('/event/'+eventId+'/delete', {csrf_token: csrfToken}, function(res) {
      location.reload()
    })
  }
}