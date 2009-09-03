#!/usr/bin/env perl

use Test::More;
plan skip_all => "Test::Pod 1.14 required for testing POD" if $@;
eval "use Test::Pod 1.14";
all_pod_files_ok();
