function classBrowser () {
    this.detail = $('#detail');
};

classBrowser.prototype.classInfoForClassName = function(e) {
    var $elt = $(e.target);

    e.preventDefault();
    this.detail.load( $elt.prop('href'));
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
    $('body').on('click', 'a.class-detail', this.classInfoForClassName.bind(this));
//    $('body').on('click', '.perl-module-file', this.showPerlModule.bind(this));
};
