use ExtUtils::MakeMaker;

use strict;
use warnings;

# Add the `devtest` target to run regression and POD tests in one go
# Beware the unexpanded tabs in this block!
sub MY::postamble {
    return <<'END';
devtest :
	REGRESSION_TESTS=1 POD_TESTS=1 $(MAKE) test

END
}

# Override `disttest` so it would behave as `devtest`
# Beware the unexpanded tabs in this block!
sub MY::dist_test {
    return <<'END';
disttest : distdir
	cd $(DISTVNAME) && $(ABSPERLRUN) Makefile.PL
	cd $(DISTVNAME) && $(MAKE) $(PASTHRU)
	cd $(DISTVNAME) && $(MAKE) devtest $(PASTHRU)

END
}

my %MAIN_REQ = (
    'RPC::ExtDirect'    => '3.30.0',
    'Mojolicious'       => '7.60',
);

WriteMakefile(
    NAME         => 'Mojolicious::Plugin::ExtDirect',
    VERSION_FROM => 'lib/Mojolicious/Plugin/ExtDirect.pm',
    ABSTRACT     => 'RPC::ExtDirect gateway for Mojolicious apps',
    AUTHOR       => 'Alex Tokarev',
    LICENSE      => 'perl',
    PREREQ_PM     => \%MAIN_REQ,

    META_MERGE => {
        resources => {
            bugtracker => 'https://github.com/nohuhu/Mojolicious-Plugin-ExtDirect/issues',
            repository => {
                url => 'git://git@github.com:nohuhu/Mojolicious-Plugin-ExtDirect.git',
                web => 'https://github.com/nohuhu/Mojolicious-Plugin-ExtDirect',
                type => 'git',
            },
        },
    },
);

