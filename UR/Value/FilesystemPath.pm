package UR::Value::FilesystemPath;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::FilesystemPath',
    is => ['UR::Value::Text'],
    english_name => 'filesystem path',
);

1;
#$Header$
