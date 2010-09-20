use warnings;
use strict;

use File::Basename;
use lib File::Basename::dirname(__FILE__)."/../../../lib";
use lib File::Basename::dirname(__FILE__)."/../..";
use UR;
use Test::More tests => 10;

use UR::Object::View::Default::Xsl qw/url_to_type type_to_url/;

my @ct = qw{
  genome/instrument-data  Genome::InstrumentData
  genome                  Genome
  genome/foo-bar/baz      Genome::FooBar::Baz
  funky-town              FunkyTown
  funky-town/oklahoma     FunkyTown::Oklahoma
};

for ( my $i = 0 ; $i + 1 < @ct ; $i += 2 ) {
    is( url_to_type( $ct[$i] ), $ct[ $i + 1 ], 'url_to_type ' . $ct[$i] );
    is( type_to_url( $ct[ $i + 1 ] ),
        $ct[$i], 'type_to_url ' . $ct[ $i + 1 ] ); 
}


