var Template = {
  template: function(templateString, data) {
    var data = data || {}
    return _.template(templateString, data, {
      interpolate: /\{\{-(.+?)\}\}/g,
      escape: /\{\{(.+?)\}\}/g
    })
  },
  
  renderComment: function(eventId) {
    var event = $('#event_'+eventId+'_actions')
    var rendered = this.template($('#comment-template').html(), {eventId: eventId})
    event.find('a#reply').css('display', 'none')
    event.append(rendered)
  }
}