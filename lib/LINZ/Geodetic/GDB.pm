#!/usr/bin/perl

=head1 Package LINZ::Geodetic::GDB

Module to obtain summary mark information from the LINZ online 
geodetic database.  Retrieves and decodes JSON data for a mark 
using the mode=js option on the geodetic database.

Synopsis:

    use LINZ::Geodetic::GDB qw/SetupMarkCache GetGdbMark/;
    
    # Initiallize the module to use a persistent local mark cache
    SetupMarkCache();

    # Retrieve the data for mark 'ABCD'
    my $code='ABCD';
    my $markdata=GetGdbMark($code);

    # Extract information from the mark
    my $coord=$markdata->{official_coordinate};
    ...


=cut

use strict;

package LINZ::Geodetic::GDB;

use base qw(Exporter);
use DBI;
use JSON;
use LWP::Simple;
use Carp;

our @EXPORT=qw(
   SetupGdbCache
   GetGdbMark
   );

our $VERSION=1.0.0;

our $gdburl='http://www.linz.govt.nz/gdb?mode=js&code={code}';
our $cacheFile="~/.gdbjsoncache";
our $useFileCache=0;
our $cacheExpiry=6;
our $markCache={};
our $debugGdb=0;

=head2 LINZ::Geodetic::GDB::SetupGdbCache(filename=>'~/.gdbjsoncache',useCache=>1,expiryHours=>6)

Set up the GDB module to cache mark data in an SQLite file store.  

=cut

sub SetupGdbCache
{
    my(%options)=@_;
    $cacheFile=$options{filename} || $cacheFile;
    $cacheFile=~s/^\~/$ENV{HOME}/;
    $cacheExpiry=$options{expiryHours} || $cacheExpiry;
    $useFileCache=exists $options{useCache} ? $options{useCache} : 1;
}

sub _getFromFileCache
{
    my( $code )=@_;
    return '' if ! $useFileCache;
    return '' if ! -e $cacheFile;
    print "Checking cache for $code\n" if $debugGdb;
    my $stndata='';
    eval
    {
        my $dbh=DBI->connect('dbi:SQLite:dbname='.$cacheFile);
        my $dateoffset='-'.$cacheExpiry.' hours';
        $dbh->do("delete from gdb_json where cachedate < datetime('now','$dateoffset')");
        ($stndata)=$dbh->selectrow_array(
            'select json from gdb_json where code=?',
            {},uc($code));
    };
    if( $@ )
    {
        print $@ if $debugGdb;
    }
    return $stndata;
}

sub _saveToFileCache
{
    my( $code, $stndata )=@_;
    return if ! $useFileCache;
    print "Saving $code to cache\n" if $debugGdb;
    eval
    {
        my $dbh=DBI->connect('dbi:SQLite:dbname='.$cacheFile);
        $dbh->do(" create table if not exists gdb_json(
                  code varchar(4) not null primary key,
                  cachedate datetime not null,
                  json text not null)");
        $dbh->do(" insert or replace into gdb_json(code,cachedate,json)
                  values (?,datetime('now'),?)",{},uc($code),$stndata);
    };
    if( $@ )
    {
        print $@ if $debugGdb;
    }
}


=head2 my $markdata=LINZ::Geodetic::GDB::GetGdbMark($code)

Retrieve information for a geodetic mark. The data is retrieved as a 
hash which is built from the JSON returned by the geodetic 
database 'mode=js' option.

By default attempts to use and save cached mark data, but can take a 
second parameter which if 0 will prevent caching.

Throws an exception if the database is not accessible or the mark 
not defined.

=cut


sub GetGdbMark
{
    my($code,$cache)=@_;
    $cache=1 if scalar(@_) < 2;
    croak("$code is not a valid geodetic code\n") if $code !~ /^\w{4}$/;
    $code=uc($code);
    return $markCache->{$code} if $cache && exists($markCache->{$code});
    my $markdata=_getFromFileCache($code);
    if( ! $markdata )
    {
        my $url=$gdburl;
        $url =~ s/\{code\}/$code/g;
        print "Retrieving $url\n" if $debugGdb;
        $markdata=get($url);
        croak("Cannot connect to geodetic database\n") if ! defined $markdata;
        $markdata =~ s/^\s*//;
        $markdata =~ s/\s*$//;
        _saveToFileCache($code,$markdata);
    }
    croak("$code is not an existing geodetic mark\n") if $markdata eq 'null';
    my $mark=decode_json($markdata);
    $markCache->{$code}=$mark if $cache;
    return $mark;
}

1;
