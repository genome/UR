function classBrowser () {

};

classBrowser.prototype.classInfoForPath = function(e) {
    var $elt = $(e.target),
        path = $elt.attr('data-path');

    e.preventDefault();
    $.ajax({url: '/class-info-for-path',
            type: 'POST',
            dataType: 'html',
            data: { path: path },
            success: function(html) {
                $('#detail').html(html);
            }
        });
};

//classBrowser.prototype.showPerlModule = function(e) {
//    var $elt = $(e.target),
//        class_name = $elt.attr('data-class-name'),
//        line = $elt.attr('data-line'),
//        url = '/render-perl-module/' + class_name;
//
//
//    if (line !== undefined) {
//        url += '#' + line;
//    }
//    $('#detail').load(url);
//};

classBrowser.prototype.run = function() {
    $('#classes-by-path').on('click', 'a', this.classInfoForPath.bind(this));
//    $('body').on('click', '.perl-module-file', this.showPerlModule.bind(this));
};
