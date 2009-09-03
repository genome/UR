package UR::Object::Property::Compressable;

use strict;
use warnings;
use Carp;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw (compressed_attributes _do_bz_compress _do_bz_decompress _do_gz_compress _do_gz_decompress);

use constant WIN32_BZIP_PATH => '//winsvr.gsc.wustl.edu/gsc/bin/bzip2.exe';

BEGIN {
    if (($^O eq 'MSWin32' || $^O eq 'cygwin') and $] <= 5.008) {
        1;
    } else {
        # Older versions of the Windows perl libs don't have the compression modules installed
        eval "use Compress::Bzip2";
        eval "use Compress::Zlib";
    }
}

sub compressed_attributes {
my($class,@attrs) = @_;

    foreach my $attr_name ( @attrs ) {
        my($subname,$type) = ($attr_name =~ m/^(\w+)_(\w*Z)$/i);
        next unless ($subname && $type);

        $type = lc($type);
        my $compressor = sprintf("_do_%s_compress", $type);
        my $decompressor = sprintf("_do_%s_decompress", $type);

        my $sub = sub {
                      my($self,$value) = @_;
                      my $data = $self->$decompressor($self->$attr_name());

                      if (defined $value && ($value ne $data)) {
                          $data = $self->$attr_name($self->_compressor($value));
                      }

                      return $data;
                  };
        # Insert the sub into the caller package's namespace
        { no strict 'refs';
            *{$class . "::" . $subname} = $sub;
        }
    }
    { 
        no strict 'refs'; 
        *{$class . "::_do_gz_compress"} = \&_do_gz_compress;
        *{$class . "::_do_bz_compress"} = \&_do_bz_compress;
        *{$class . "::_do_gz_decompress"} = \&_do_gz_decompress;
        *{$class . "::_do_bz_decompress"} = \&_do_bz_decompress;
    }
}

sub _do_gz_compress {
my($self,$value) = @_;
    my $new_compressed;
#    if ($^O eq 'MSWin32' || $^O eq 'cygwin') {
#        die "_do_gz_compress unimplimented on Win32";
#    } else {
        $new_compressed = Compress::Zlib::memGzip($value);
#    }
    return $new_compressed;
}


sub _do_gz_decompress {
my($self,$value) = @_;
    my $new_decompressed;
#    if ($^O eq 'MSWin32' || $^O eq 'cygwin') {
#        die "_do_gz_decompress unimplimented on Win32";
#    } else {
        $new_decompressed = Compress::Zlib::memGunzip($value);
#    }
    return $new_decompressed;
}

sub _do_bz_compress {
my($self,$value) = @_;

    my $new_compressed = '';

    if (($^O eq 'MSWin32' || $^O eq 'cygwin') and $] <= 5.008) {
        # Compress::Bzip2 dosen't work on windows, but we do have a bzip2 exe
        unless (-x WIN32_BZIP_PATH) {
            croak "Can't execute bzip2 program " . WIN32_BZIP_PATH;
        }

        my $filename = "/bziptmp$$";
        my $fh = IO::File->new("> $filename") || croak "Can't create temp file for bzipping: $!";
        $fh->print($value);
        $fh->close();

        my $cmdline = WIN32_BZIP_PATH . " -z $filename";
        `$cmdline`;

        $filename .= ".bz2";
        $fh = IO::File->new($filename);
        while(<$fh>) {
            $new_compressed .= $_;
        }
        unlink $filename;

    } else {
        my($new_fh);
        open($new_fh, '>', \$new_compressed);
        binmode($new_fh);

        my $bz=bzopen($new_fh, "wb");
        $bz->bzwrite($value);
        $bz->bzclose;
    }
    return $new_compressed;
}
        

sub _do_bz_decompress {
my($self,$value) = @_;
    my $new_decompressed;

    if (($^O eq 'MSWin32' || $^O eq 'cygwin') and $] <= 5.008) {
        unless (-x WIN32_BZIP_PATH) {
            croak "Can't execute bzip2 program " . WIN32_BZIP_PATH;
        }

        my $filename = "/bziptmp$$" . ".bz2";
        my $fh = IO::File->new("> $filename") || croak "Can't create temp file for bzipping: $!";
        $fh->print($value);
        $fh->close();

        my $cmdline = WIN32_BZIP_PATH . " -d $filename";
        `cmdline`;

        ($filename) = ($filename =~ m/(\w+)\.bz2$/);
        $fh = IO::File->new($filename);
        while(<$fh>) {
            $new_decompressed .= $_;
        }
        unlink $filename;
  
    } else {
        my $old_fh;
        open($old_fh, '<', \$value);
        binmode($old_fh);

        my $bz=bzopen($old_fh, "rb");
        my $buffer;
        while($bz->bzread($buffer)) {
            $new_decompressed .= $buffer;
        }
        $bz->bzclose;
    }

    return $new_decompressed;
}

1;
