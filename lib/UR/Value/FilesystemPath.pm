package UR::Value::FilesystemPath;

use strict;
use warnings;
require UR;
our $VERSION = "0.41_01"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::FilesystemPath',
    is => 'UR::Value::Text',
);

sub exists {
    return -e shift;
}

sub is_dir {
    return -d shift;
}

sub is_file {
    return -f shift;
}

sub is_symlink {
    return -l shift;
}

sub size {
    return -s shift;
}

1;
