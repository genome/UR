package UR::Test;
use strict;
use warnings;
require UR;
our $VERSION = "0.391"; # UR $VERSION;
use Test::More;

sub check_properties {
    my $o_list = shift;    
    my %params = @_;
    
    my $skip = delete $params{skip};

    if (%params) {
        die "odd params passed: " . join(" ", %params);
    }

    ok(
        scalar(@$o_list), 
        "got " . scalar(@$o_list) . " objects "
        . " of type " . ref($o_list->[0])
    );

    my $cn = ref($o_list->[0]);
    my $c = UR::Object::Type->get($cn);
    ok($c, "got class meta for $cn");

    my @pm = 
        map { $_->[1] }
        sort { $a->[0] cmp $b->[0] }
        map { [ $_->property_name, $_ ] }
        $c->all_property_metas;
        
    ok(scalar(@pm), "got " . scalar(@pm) . " properties");

    if ($skip) {
        $skip = { map { $_ => 1 } @$skip }; 
        my @pm_remove;
        my @pm_keep;
        for my $p (@pm) {
            if ($skip->{$p->property_name}) {
                push @pm_remove, $p;
            }
            else {
                push @pm_keep, $p;
            }
        }
        if (@pm_remove) {
            note(
                'skipping ' . (@pm_remove) . " properties: "
                . join(", ", map { $_->property_name } @pm_remove)
            );
            @pm = @pm_keep;
        }
    }

    my (@v,$v, $last_property_name);
    for my $pm (@pm) {
        my $p = $pm->property_name;
         
        next if defined($last_property_name) and $p eq $last_property_name;
        $last_property_name = $p;
        
        my $is_mutable = $pm->is_mutable;
        my $is_many = $pm->is_many;
        my %errors;
        #diag($p);
        for my $o (@$o_list) {
            eval {
                if ($is_many) {
                    @v = $o->$p();
                    if ($is_mutable) {
                        #$o->$p([]);
                        #$o->$p(\@v);
                    }
                }
                else {
                    my $v = $o->$p();
                    if ($is_mutable) {
                        #$o->$p(undef);
                        #$o->$p($v);
                    }
                }
            };
            if ($@) {
                my ($e) = split(/\n/,$@);
                my $a = $errors{$e} ||= [];
                push @$a, $o;
            }
        }
        my $msg;
        if (%errors) {
            for my $error (keys %errors) {
                my $objects = $errors{$error};
                $msg .= 'on ' . scalar(@$objects) . ' of ' . scalar(@$o_list) . "objects: " . $error;
                chomp $msg;
                $msg .= "\n";
            }
        }
        ok(!$msg, "property check: $p") or diag $msg;
    }
}

1;

