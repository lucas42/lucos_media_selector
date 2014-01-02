{
	var existingtags = null;
	
	$(function (){
		$("tr:not(.static) td:not(.id)").each(makeInput);
		$("<button />").text("Add Row").click(addRow).insertAfter('table');
		$("<button />").text("Cancel").click(function(){ window.close(); }).insertAfter('table');
		$.loadApi('tags', null, function(data) {existingtags = data.tags; $('.label input').each(function (){ $(this).autocomplete({source: existingtags});});});
		$(document).keyup(function (e) { 
				switch (e.keyCode) {
					case 65: //a 
						addRow();
						break;
					case 27: //ESC 
						window.close(); 
						break;
				}
			});
	});

	function addRow() {
			var id = $("<td />").addClass("id");
			var label = $("<td />").addClass("label").each(makeInput);
			var func = $("<td />").addClass("function").each(makeInput);
			$("<tr />").append(id).append(label).append(func).appendTo("table");
			label.children("input").focus();
	}
	
	function saveRow() {
		return alert("Not yet implemented");
		$.hideErrors();
		var row = $(this).parents("tr");
		var label = row.find('.label input');
		var value = row.find('.value input');
		var source = row.children(".source");
		var duplicate = false;
		$('.label input').each(function () {
			if (($(this).data('orig-text') == label.val()) && ($(this).parents('tr').data('tagid') != row.data('tagid'))) {
				duplicate = true;
				return false;
			}
		});
		if (duplicate) {
			$.showError("Cannot create another row with the same label - edit the existing one");
			return false;
		}
		row.find('.source button').attr('disabled', 'disabled');
		label.setOrigText();
		value.setOrigText();
		var params = {trackid: row.parents('table').data('trackid'), tag: label.val(), value: value.val()};
		$.loadApi('update', params, function(data) {
			source.empty().text(data.source);
			row.data('tagid', data.tagid);
			row.find("input").blur();
		});
	}
	$.fn.setOrigText = function () {
		$(this).data("orig-text", $(this).val());
		return this;
	}

	function showSave() {
		if ($(this).val() == $(this).data("orig-text")) return;
		var source = $(this).parents('tr').children('.source');
		source.text("");
		$("<button />").text("Save").mouseup(saveRow).appendTo(source);
	}

	function makeInput () {
		var td = $(this);
		var text = td.text();
		td.text("");
		var input = $("<input />").val(text).setOrigText().bind("change keyup paste", showSave).keyup(function (e) { 
			e.stopPropagation();
			if (e.keyCode == 13) return $(this).each(saveRow); 
			if (e.keyCode == 27) $(this).blur(); 
		} ).appendTo(td);
		if (td.hasClass('label') && existingtags) input.autocomplete({source: existingtags, autofocus: true});
	}

};
