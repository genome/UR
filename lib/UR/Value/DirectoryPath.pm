package UR::Value::DirectoryPath;

use strict;
use warnings;

require UR;
our $VERSION = "0.42_03"; # UR $VERSION;

UR::Object::Type->define(
    class_name => 'UR::Value::DirectoryPath',
    is => ['UR::Value::FilePath'],
);

1;
#$Header$
