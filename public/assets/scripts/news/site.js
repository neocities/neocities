var Site = {
  toggleFollow: function(siteId, csrfToken) {
    var link = $('a#followLink')
    var span = $('a#followLink span')
    $.post('/site/'+siteId+'/toggle_follow', {csrf_token: csrfToken}, function(res) {
      console.log(res)
      if(res.result == "followed") {
        span.text('Unfollow')
        link.removeClass('follow')
      } else if(res.result == 'unfollowed') {
        span.text('Follow')
        link.addClass('follow')
      }
    })
  }
}
