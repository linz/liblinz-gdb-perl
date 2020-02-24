#!/usr/bin/perl

=head1 Package LINZ::GDB

Module to obtain summary mark information from the LINZ online 
geodetic database.  Retrieves and decodes JSON data for a mark 
using the mode=js option on the geodetic database.

Synopsis:

    use LINZ::GDB qw/SetupGdbCache GetGdbMark/;
    
    # Initiallize the module to use a persistent local mark cache
    SetupGdbCache();

    # Retrieve the data for mark 'ABCD'
    my $code='ABCD';
    my $markdata=GetGdbMark($code);

    # Extract information from the mark
    my $coord=$markdata->{coordinate};
    ...


=cut

use strict;

package LINZ::GDB;

use base qw(Exporter);
use DBI;
use JSON;
use LWP::UserAgent;
use Carp;

our @EXPORT=qw(
   SetGdbOptions
   GetGdbMark
   );

our $VERSION=1.0.0;

our $gdburl='https://www.geodesy.linz.govt.nz/api/gdbweb/mark?&code={code}';
our $cacheFile="~/.gdbjsoncache";
our $useFileCache=0;
our $cacheExpiry=6;
our $markCache={};
our $debugGdb=0;
our $timeout=15;
our $gdbfailed=0;

=head2 LINZ::GDB::SetGdbOptions(%options)

Set up the GDB module to cache mark data in an SQLite file store, as well as other
options

Options can include:

=over

=item useCache

If true then a persistent file cache will be used

=item filename

The name of the cache file for storing.  Can include a leading ~ which is replaced
with the HOME, APPDATA, or TEMP environment variable.

=item expiryHours

The time in hours for which cached mark data is considered valid

=item timeout

The timout in seconds for URL requests.  Once a request has failed no other 
requests are attempted.

=back

=cut

sub SetGdbOptions
{
    my(%options)=@_;
    $cacheFile=$options{filename} || $cacheFile;
    my $home=$ENV{HOME} || $ENV{APPDATA} || $ENV{TEMP};
    $cacheFile=~s/^\~/$home/;
    $cacheExpiry=$options{expiryHours} || $cacheExpiry;
    $useFileCache=exists $options{useCache} ? $options{useCache} : 1;
    $timeout=exists $options{timeout} ? $options{timeout}+0 : $timeout;
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


=head2 my $markdata=LINZ::GDB::GetGdbMark($code)

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
        if( ! $gdbfailed )
        {
            my $url=$gdburl;
            $url =~ s/\{code\}/$code/g;
            print "Retrieving $url\n" if $debugGdb;
            my $ua=LWP::UserAgent->new;
            $ua->timeout($timeout);
            $ua->env_proxy;
            my $response=$ua->get($url);
            if( $response->is_success )
            {
                $markdata=$response->decoded_content;
                $markdata =~ s/^\s*//;
                $markdata =~ s/\s*$//;
                _saveToFileCache($code,$markdata);
            }
            else
            {
                $gdbfailed=1;
            }
        }
        croak("Cannot connect to geodetic database\n") if $gdbfailed;
    }
    croak("$code is not an existing geodetic mark\n") if $markdata eq 'null';
    my $mark=decode_json($markdata);
    $markCache->{$code}=$mark if $cache;
    return $mark;
}

1;
