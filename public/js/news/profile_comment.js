var ProfileComment = {
  commentContent: function(eventId) {
    return $('#event_'+eventId+' > div.content').first()
  },

  displayEditor: function(eventId) {
    var commentDiv = this.commentContent(eventId)
    var eventActions = $('#event_'+eventId+'_actions').first()
    var rendered = Template.template($('#comment-edit-template').html(), {
      eventId: eventId,
      content: commentDiv.text()
    })

    eventActions.find('a#editLink').css('display', 'none')

    commentDiv.data('original-html', commentDiv.html())
    commentDiv.addClass('is-editing')
    commentDiv.html($.trim(rendered))
    commentDiv.find('textarea').focus()
  },

  cancelEditor: function(eventId) {
    var eventActions = $('#event_'+eventId+'_actions').first()
    var commentDiv = this.commentContent(eventId)
    eventActions.find('a#editLink').css('display', 'inline')
    commentDiv.removeClass('is-editing')
    commentDiv.html(commentDiv.data('original-html'))
  },

  update: function(eventId, csrfToken) {
    var commentDiv = this.commentContent(eventId)
    var message = commentDiv.find('textarea').val()

    $.post('/event/'+eventId+'/update_profile_comment', {
      csrf_token: csrfToken,
      message: message
    }, function(res) {
      if(res.result == 'success') {
        $('#event_'+eventId+'_actions').first().find('a#editLink').css('display', 'inline')
        commentDiv.removeClass('is-editing')
        commentDiv.text(message)
      }
    })
  }
}
