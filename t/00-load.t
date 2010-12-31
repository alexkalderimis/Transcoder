#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Transcoder' ) || print "Bail out!
";
}

diag( "Testing Transcoder $Transcoder::VERSION, Perl $], $^X" );
