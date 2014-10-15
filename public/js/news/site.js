var link = $('a#followLink');

var Site = {
  toggleFollow: function(siteId, csrfToken) {
    $.post('/site/'+siteId+'/toggle_follow', {csrf_token: csrfToken}, function(res) {
      if(res.result == "followed") {
        link.addClass('is-following')        
      } else if(res.result == 'unfollowed') {
        link.removeClass('is-following')
      }
    })
  }
};

$('a#followLink').hover(function() {
  if (link.hasClass('is-following')) {
    $('a#followLink').addClass('unfollow');
  }
}, function() {
  $('a#followLink').removeClass('unfollow');
});