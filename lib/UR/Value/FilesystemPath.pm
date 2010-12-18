package UR::Value::FilesystemPath;

use strict;
use warnings;
require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::FilesystemPath',
    is => 'UR::Value',
);

1;
