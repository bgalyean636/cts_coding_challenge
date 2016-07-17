#!/bin/perl

$file = 20160201;
for ( $i = 0; $i < 60; $i++ ) {
	open ( FILE , ">../log/$file.log" );
	close ( FILE );
	$file += 1;
	if ( $file == 20160230 ) {
		$file = 20160301;
	}
	print "$i,$file\n";
}