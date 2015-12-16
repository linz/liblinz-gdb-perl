#!usr/bin/perl
use strict;
use warnings;

use Config;
use Module::Build;

my $requires = {
    'Carp' => 0,
    'DBI' => 0,
    'DBD::SQLite' => 0,
    'JSON' => 0,
};

my $build =  Module::Build->new(
    module_name        => 'LINZ::GDB',
    license            => 'bsd',
    dist_author        => 'LINZ',
    dist_version_from  => 'lib/LINZ/GDB.pm',
    dist_abstract      => 'Module to retrieve mark information from the geodetic database',
    requires           => $requires,
    create_makefile_pl => 'small',
);

$build->create_build_script;
