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

classBrowser.prototype.classPropertyDetailHover = function(e) {
    var that = this;
    var openPopover = function() {
            var $row = $(e.currentTarget);
            $.get( $row.attr('data-popover-load'),
                function(html) {
                    that.popover = $row.popover({ html: true, placement: 'top', content: html});
                    that.popover.popover('show');
                });
    };
    var closePopover = function() {
            that.popover.popover('destroy');
    };
    if (this.hoverTimer) {
        clearTimeout(this.hoverTimer);
        this.hoverTimer = null;
    } else {
        this.hoverTimer = setTimeout(function() {
            if (that.popover) {
                closePopover();
            } else {
                openPopover();
            }
        })
    }
};

classBrowser.prototype.run = function() {
    $('body').on('click', 'a.class-detail', this.classInfoForClassName.bind(this));
    this.detail.on('change', '[name="show-properties"]', this.showHideClassProperties.bind(this));
    this.detail.on('mouseenter mouseleave', 'table.class-properties tbody tr', this.classPropertyDetailHover.bind(this));
};
