package UR::Value::DirectoryPath;

use strict;
use warnings;

require UR;

UR::Object::Type->define(
    class_name => 'UR::Value::DirectoryPath',
    is => ['UR::Value::FilesystemPath'],
    english_name => 'directory path',
);

1;
#$Header$
