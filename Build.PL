use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Transcoder',
    license             => 'perl',
    dist_author         => q{Alex Kalderimis <alexkalderimis@gmail.com>},
    dist_version_from   => 'lib/Transcoder.pm',
    build_requires => {
        'Test::More' => 0,
    },
    add_to_cleanup      => [ 'Transcoder-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
