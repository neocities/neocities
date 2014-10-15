var Site = {
  toggleFollow: function(siteId, csrfToken) {
    var link = $('a#followLink')
    $.post('/site/'+siteId+'/toggle_follow', {csrf_token: csrfToken}, function(res) {
      if(res.result == "followed") {
        link.addClass('is-following')        
      } else if(res.result == 'unfollowed') {
        link.removeClass('is-following')
      }
    })
  }
}
