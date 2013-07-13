$(document).ready(function() {	

	// do scrolly things on scroll
	$(window).bind('scroll', function(){
		if($(this).scrollTop() > 460) {
			$(".header-Nav").addClass('add-Stripe');
		}
		if($(this).scrollTop() < 460) {
			$(".header-Nav").removeClass('add-Stripe');
		}
		
		if($(this).scrollTop() > 100) {
			$(".hp-Logo").addClass('in-View');
			$(".constant-Nav").addClass('in-View');
		}
		if($(this).scrollTop() < 100) {
			$(".hp-Logo").removeClass('in-View');
			$(".constant-Nav").removeClass('in-View');
		}
	});
	
	$('.small-Nav').click(function(){
  	$('.header-Nav').toggleClass('show-Nav');
	})

});
