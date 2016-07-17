#!/bin/perl
use warnings;
use strict;
use DBI;
use DBD::mysql;
use Time::Piece;
use File::FindLib 'lib';
use ALLOCATION_CONFIGS;

##############################################################
# Script      : query_database.pl
# Author      : Brad Galyean (bgalyean)
# Date        : 05/01/2016
# Last Edited : 05/01/2016, bgalyean
# Description : called by monthly allocation script. Handles connection to
#               the database and dumps employee data into dat file.
##############################################################


# Define the select query to be executed in database.
my $database_query = 	"select emp_id, last_name, first_name, role, " 
						. "department, manager from organization";

# This creates the mysql connection.
my $connection = ConnectToMySql();
if ( $connection =~ /^ERROR/ ) {
	return $connection;
}

# The result of $database_query will be dumped in this file.
my $file = get_config( "ROOT_DIR" ) . get_config( "EMPLOYEE_DATA_FILE" );
if ( $file ) {
	open (OUT, ">$file") or return "Could not open $file: $!";
}
else {
	return "EMPLOYEE_DATA_FILE not configured in monthly_allocations.cfg";
}


# Grab the date in YYYYMMDD format. Will be placed in the header of dump file
# and checked for verification.
my $date = localtime->strftime('%Y%m%d');

# The record_count variable will record the total number of records retrieved
# and place into the trailer of the data file.
my $record_count = 0;

# Add the date to the header. 
print OUT "#HEADER|$date\n";

# Execute the database query and dump result into out file. 
query_database();

# Add the record count total to the trailer. 
print OUT "#TRAILER|$record_count";
close (OUT);

return "Success";

##############################################
### Sub-Functions defined below this line. ###
##############################################

sub ConnectToMySql {
	open (ACCESS_INFO, "../cfg/accessDB.dat") or return  
													"Can't access "
													. "accessDB.dat: $!";
	my $database = <ACCESS_INFO>;
	my $host = <ACCESS_INFO>;
	my $userid = <ACCESS_INFO>;
	my $passwd = <ACCESS_INFO>;
	chomp ($database,$host,$userid, $passwd);
	close (ACCESS_INFO);
	my $connectionInfo = "dbi:mysql:$database;$host";
	my $l_connection = 	DBI->connect($connectionInfo,$userid,$passwd) 
						or return "ERROR: $DBI::errstr";
	return $l_connection;
}


sub query_database {
	my $statement = $connection->prepare($database_query);
	$statement->execute();
	while (my @data = $statement->fetchrow_array()) {
		print OUT "$data[0]|$data[1]|$data[2]|$data[3]|$data[4]|$data[5]\n";
		$record_count++;
	}
}