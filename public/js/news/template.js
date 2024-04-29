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
    var eventForms = event.find('form')

    if(eventForms.length > 0) {
      eventForms[0].remove()
      return false
    }

    var rendered = this.template($('#comment-template').html(), {eventId: eventId})
    event.append(rendered)
  }
}