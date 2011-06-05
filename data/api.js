$.fn.showError = function (message) {
	var parent = $(this);
	parent.children('.error').remove();
	var close = $("<span />").addClass("errorclose").text('☒').click( function () { $(this).parents(".error").remove(); } );
	$("<span />").addClass('error').text(message).append(close).prependTo(parent);
	return this;
}
jQuery['showError'] = function (message) {
	$('body').showError(message);
}
$.fn.hideErrors = function () {
	$(this).find('.error').remove();
	return this;
}
jQuery['hideErrors'] = function () {
	$('.error').remove();
}
jQuery['loadApi'] = function (method, params, success) {
	function httpError(e, jqxhr, settings, exception) {
		$.showError("Failed to retrieve "+settings.url);
	}
	
	function ajaxReturned(data) {
		if (data.error) return $('body').showError(data.error);
		if (success) success(data);
	}
	$.get("/api/" + method, params, ajaxReturned).error(httpError);
	return this;
}
