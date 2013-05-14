( function($) {

    $.fn.sortableTable = function() {
        this.each(function() {
            var $table = $(this);
            if (! $table.is('table')) {
                return; // Only works for tables
            }
            var sorted_column;
            $table.on('click', 'th', function(e) {
                var $th = $(e.currentTarget),
                    index = $th.index()+1,
                    $rows = $table.find('tbody tr');

                $rows.sort(function(a,b) {
                    var selector = 'td:nth-child('+index+')';
                    var a_text = $(a).find(selector).text().replace(/^\s+|\s+$/g,''),

                        b_text = $(b).find(selector).text().replace(/^\s+|\s+$/g,'');
                    var sort_result = a_text.localeCompare(b_text);
                    if (index === sorted_column) {
                        // Already sorted by this column, do a reverse sort
                        sort_result = 0-sort_result;
                    }
                    return sort_result;
                });

                // Update the sorted column.  If we just did a reverse sort, then
                // forget the previous sorted column so that if the user clicks
                // the same column yet again, they'll get that same column sorted
                // the normal way
                sorted_column = ( index === sorted_column ) ? undefined : index
                
                var $last;
                $rows.each(function(i, tr) {
                    var $tr = $(tr);
                    if ($last) {
                        $last.after($tr);
                    } else {
                        $table.find('tbody').prepend($tr);
                    }
                    $last = $tr;
                });
            });
        });
    };
})(jQuery);
