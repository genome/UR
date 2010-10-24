package UR::Object;

# parts of the UR::Object API removed at revision 0.17

use warnings;
use strict;

use Data::Dumper;
use Scalar::Util qw(blessed);

sub preprocess_params {
    Carp::confess("preprocess_params!");
    if (@_ == 2 and ref($_[1]) eq 'HASH') {
        # already processed, just throw it back to the caller
        if (wantarray) {
            # ... after flattening it out
            return %{ $_[1] };
        }
        else {
            # .. just the reference
            return $_[1];
        }
    }
    else {
        my $class = shift;
        $class = (ref($class)?ref($class):$class);

        # get the rule object, which has the old params pre-cached
        my ($rule, @extra) = $class->can("define_boolexpr")->($class,@_);
        my $normalized_rule = $rule->normalize;
        my $rule_params = $normalized_rule->legacy_params_hash;

        # catch only case where sql is passed in
        if (@extra == 2 && $extra[0] eq "sql"
            && $rule_params->{_unique} == 0
            && $rule_params->{_none} == 1
            && (keys %$rule_params) == 2
        ) {

            push @extra,
                "_unique" => 0,
                "_param_key" => (
                    ref($extra[1])
                        ? join("\n", map { defined($_) ? "'$_'" : "undef"} @{$extra[1]})
                        : $extra[1]
                );

            if (wantarray) {
                return @extra;
            }
            else {
                return { @extra }
            }
        }

        if (wantarray) {
            # flatten out the cached params hash
            #return %{ $rule->{legacy_params_hash} };
            return %{ $rule_params }, @extra;
        }
        else {
            # duplicate the reference, and return the duplicate
            #return { %{ $rule->{legacy_params_hash} } };
            return { %{ $rule_params }, @extra };
        }
    }
}

# when deprecated parts of the API are removed, they will go into a compatability module which will be used below:
# use UR::API::removed_from_v0_XX;

1;

