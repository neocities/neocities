var Template = {
  template: function(templateString, data) {
    var data = data || {}
    return _.template(templateString, data, {interpolate: /\{\{(.+?)\}\}/g})
  },
  
  renderComment: function(event_id) {
    var event = $('#event_'+event_id+'_actions')
    var rendered = this.template($('#comment-template').html(), {event_id: event_id})
    event.find('a#reply').css('display', 'none')
    event.append(rendered)
  }
}