# Makefile.PL
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME         => 'IPC::Wrangler',
    ABSTRACT     => 'Coordinated inter-process communication',
    AUTHOR       => 'Brett Watson <brett.watson@gmail.com>',
    VERSION_FROM => 'lib/IPC/Wrangler.pm',
    LICENSE      => 'perl_5',
    PREREQ_PM    => {
        'JSON::MaybeXS' => '1.004000',
        'AnyEvent'      => 0,
    },
    META_MERGE   => {
        resources => {
            repository => 'https://github.com/TFBW/IPC-Wrangler',
        },
    },
    );
