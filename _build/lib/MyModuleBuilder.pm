package MyModuleBuilder;
use Module::Build;
@ISA = qw(Module::Build);

        sub ACTION_docs {
            # ensure docs get man pages and html
            my $self = shift;
            $self->depends_on('code');
            $self->depends_on('manpages', 'html');
        }

        sub man1page_name {
            # without this we have "man ur-init.pod" instead of "man ur-init"
            my ($self, $file) = @_;
            $file =~ s/.pod$//;
            return $self->SUPER::man1page_name($file);
        }
    
1;
