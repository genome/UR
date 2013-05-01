function classBrowser () {
    this.detail = $('#detail');
};

classBrowser.prototype.classInfoForClassName = function(e) {
    var $elt = $(e.target);

    e.preventDefault();
    this.detail.load( $elt.prop('href'));
};

// Called when the checkbox is changed for show/hide inherited class properties
classBrowser.prototype.showHideClassProperties = function(e) {
    var $elt = $(e.target),
        inh_rows = this.detail.find('table.class-properties tr.inherited');

    if ($elt.prop('checked')) {
        inh_rows.show();
    } else {
        inh_rows.hide();
    }
};

classBrowser.prototype.run = function() {
    $('body').on('click', 'a.class-detail', this.classInfoForClassName.bind(this));
    this.detail.on('change', '[name="show-properties"]', this.showHideClassProperties.bind(this));
};
