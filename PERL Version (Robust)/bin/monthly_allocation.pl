#!/bin/perl
use warnings;
use strict;
use Time::Piece;
use File::FindLib 'lib';
use ALLOCATION_CONFIGS;

##############################################################
# Script      : monthly_allocation.pl
# Author      : Brad Galyean (bgalyean)
# Date        : 04/20/2016
# Last Edited : 05/10/2016, bgalyean
# Description : returns total allocation currency amount for provided
#			    employee_id <Usage: monthly_allocation.pl emp_id>
##############################################################

# Grab Employee ID from input and check it for correctness.
my $employee_id;
if ( ( $ARGV[0] ) && ( $ARGV[0] =~ /^\d{6}$/ ) ) {
	$employee_id = $ARGV[0];
}
else {
	die "Please provide a 6 digit employee ID. ( ex. script.pl 123456 )";
}


# Define variables/directory-refs used throughout this script.
my $root_directory = get_config( "ROOT_DIR" );
my $data_file = get_config( "ROOT_DIR" ) . get_config( "EMPLOYEE_DATA_FILE" );
my $run_sql_flag = get_config( "RUN_SQL" );
my $log_directory = "$root_directory/log/";
my $log_retention = get_config( "LOG_RETENTION" );
my $print_hierarchy_flag = get_config( "PRINT_HIERARCHY" );
my $current_date = localtime->strftime( '%Y%m%d' );
# End result allocation cost tracked by $total_allocation_cost.
my $total_allocation_cost = 0;
# Used for printing the hierarchy in logs and on screen (if configured).
my $hierarchy_level = 1;
# This hash-ref will contain the employee info from the data file into memory.
my %employees;


# Perform old log cleanup and open new log handle for writing.
setup_log( $current_date );
log_it( 1, "Cost Allocation lookup started for employee id: $employee_id");

if ( get_config( "LOG_RETENTION" ) ) {
	$log_retention = get_config( "LOG_RETENTION" );
	log_it (1 , "LOG_RETENTION set to max $log_retention logs in config.")
}
else {
	# If not defined in config, default to 36 to prevent inadvertent deletions.
	$log_retention = 36;
	log_it ( 2 , "LOG_RETENTION not set in config. "
				. "Defaulting to $log_retention max logs.")
}

# Deletes old logs based on retention configuration.
archive_logs ();

# Grab data from database (if configured to do so).
if ( $run_sql_flag eq 'Y' ) {
	# Grab all employee data from database.
	my $query_database_result = require 'query_database.pl';
	if ( $query_database_result ne "Success" ) {
		log_it( 3, $query_database_result );
		die "$query_database_result";
	} 
	else {
		log_it( 1, "Data retrieved from database successful.");
	}
}
else {
	log_it( 1,	"RUN_SQL is currently disabled in config. Attempting to run "
				. "allocation cost from provided file.");
}


# Perform data checks on the data (as per config settings)
# (header,footer, date, record counts, missing data, incorrect data).
my $data_check_result = require 'data_check.pl';
if ( $data_check_result ne "Success" ) {
		log_it( 3, $data_check_result);
		die "$data_check_result";
}


# Check that the data file exists, and attempt to open for reading.
if ( ! open (EMPLOYEE_DATA, "$data_file" ) ) {
	log_it ( 3 , "Could not open $data_file: $!" );
	die ( "Could not open $data_file: $!" );
}


# $verify_status is used track if the employee id was found in the data. 
# Expected results are as follows:
# 0 = employee id does not exist in flatfile
# 1 = found, and is a manager
my $verify_status = 0; 
while ( my $line = <EMPLOYEE_DATA> ) {
	# Avoid trying to process the header and footer of file.
	# Skip to next line if does not start with a digit.
	next if $line !~ /^\d/;
	
	chomp $line;
	# Assign variables to the employee's information. Data is split by pipe.
	my (	$id,
			$last_name,
			$first_name,
			$role,
			$department,
			$manager ) = split( /\|/, $line );
	
	if ( $id == $employee_id ) {
		if ( $role =~ m/Manager/i ) {
			$verify_status = 1;
		} 
		else {
			# Employee is not a manager. Therefore, no need to continue.
			log_it ( 1 , "$employee_id is not a manager: $line" );
			# Instead of die, this could be changed to a return if the calling
			# script/program needs to know the outcome.
			die "$employee_id is not a manager.";	
		}
	}
	
	# Place all employee data into a hashref. This is used later 
	# in the get_allocation sub-routine.
	$employees{$id}{LAST_NAME} = $last_name;
	$employees{$id}{FIRST_NAME} = $first_name;
	$employees{$id}{ROLE} = uc($role);
	$employees{$id}{DEPARTMENT} = $department;
	$employees{$id}{MANAGER} = $manager;
}
close (EMPLOYEE_DATA);


# End the program if employee_id is not found.
if ( $verify_status == 0 ) {
	log_it ( 1 , "$employee_id was not found." );
	# Instead of die, this could be changed to a return if the calling
	# script/program needs to know the outcome.
	die "$employee_id was not found.";
}


# Make total allocation cost equal to the Manager cost to begin with.
# (to account for themself).
$total_allocation_cost = get_employee_cost ( "MANAGER" );


# Create an array of all employee_ids. Used in get_allocation sub-routine.
my @all_employee_ids = keys(%employees);

# Print the manager's details to log and to screen (if configured to do so).
print_manager_details();

# get_allocation() loops thru all employee ids, and 
# will add the employee's allocation cost to the total_allocation_cost as
# employees and managers are found. 
get_allocation($employee_id, $hierarchy_level);

# Format to 2 decimal places ( this is a currency amount ).
$total_allocation_cost = sprintf("%.2f", $total_allocation_cost);

# Print the result details to log.
print_results_to_log();


# Returns the result. It is assumed at this time that just the allocation cost
# number is expected as a return to this script. No frills. Log contains
# details unless PRINT_HIERARCHY is set to 'Y' in config.
print sprintf("%.2f", $total_allocation_cost);



##############################################
### Sub-Functions defined below this line. ###
##############################################

# If a log for today's date does not exist, create one. Else, concatenate 
# into the existing one.
sub setup_log {
	my $current_date = $_[0];
	my $current_log = "$log_directory/$current_date.log";
	if (-e "$current_log") {
		open (LOG, ">>$current_log") or die "Could not open LOG: $!";
	}
	else {
		open (LOG, ">$current_log") or die "Could not open LOG: $!";
	}
}

# Cycle out (delete) old logs. Any log that is not in YYYYMMDD.log format
# is ignored. ( ex. 20140101_keepme.log would be kept).
# Ensures that log directory never fills up while also keep an archive of
# more recent queries.
sub archive_logs {
	opendir(LOG_FILES, "$log_directory") or die $!;
	my @log_files  = grep /^\d{8}\.log/, sort(readdir(LOG_FILES));
	my $log_count = @log_files;
	while ( $log_count > $log_retention ) {
		my $delete_log_file = "$log_directory$log_files[0]";
		unlink $delete_log_file;
		shift @log_files;
		$log_count--;
		log_it (1 , "Deleted $delete_log_file (OLD)");
	}
	closedir(LOG_FILES);
}

# Used for cleaner/simplier logging.
sub log_it {
	my ($message_type, $log_entry) = @_;
	$message_type = get_config( $message_type );
	my $timestamp = localtime->strftime( '%H:%M:%S' );
	print LOG "$current_date $timestamp [$message_type] $log_entry\n";
}

# This is where the allocation cost is tallied. We loop thru all the employee
# ids under the queried manager's id, and each time a manager is found 
# in the hierarchy, a new thread (loop) is created. This continues until no
# manager is found in the chain of command. 
sub get_allocation {
	my $manager_id = $_[0];
	my $hierarchy_level = $_[1];
	foreach ( @all_employee_ids ) {
		my $current_emp_id = $_;
		my $employees_manager_id = get_manager ( $current_emp_id );
		my $employees_role = get_role ( $current_emp_id );
		if ( $employees_manager_id == $manager_id ) {
			# Add the cost of this employee to the manager's total allocation.
			my $cost = get_employee_cost ( $employees_role );
			if ( $cost eq "" ) {
				my $err_msg = 	"The role ($employees_role) does not exist in "
								. "the cost_allocation.cfg. All roles must be "
								. "accounted for. Please account for this role"
								. "\n";
				log_it 	( 3,  $err_msg );
				die $err_msg;
				
			}
			else {
				$total_allocation_cost += $cost;
			}

			
			print_hierarchy ( $current_emp_id , $hierarchy_level , $cost);
			
			# If this employee is a manager, spawn new thread.
			# This continues until a manager is not found in hierarchy.
			if ( $employees_role =~ m/Manager/i ) {
				get_allocation ( $current_emp_id , $hierarchy_level + 1);
			}
		}
	}
}

# This function grabs the employee's manager from the hashref in memory.
# This function was created for cleaner code up top.
sub get_manager {
	my $queried_employee_id = $_[0];
	return $employees{$queried_employee_id}{MANAGER};
}

# This function grabs the employee's role from the hashref in memory.
# This function was created for cleaner code up top.
sub get_role {
	my $queried_employee_id = $_[0];
	return $employees{$queried_employee_id}{ROLE};
}

# Prints out the hierarchy as get_allocation() loops thru data.
# This function was created for cleaner code up top.
sub print_hierarchy {
	my ( $print_employee_id, $print_hierarchy_level, $print_cost ) = @_;
	my $print_string = "";
	
	# Add a tab for each hierarchy level, for readability in logs.
	while ( $print_hierarchy_level > 0 ) {
		$print_string .= "\t";
		$print_hierarchy_level--;
	}
	$print_string 	.= "$employees{$print_employee_id}{FIRST_NAME} "
					. "$employees{$print_employee_id}{LAST_NAME} "
					. "$print_employee_id "
					. "($employees{$print_employee_id}{ROLE} \$$print_cost)\n";
	print LOG $print_string;
	
	# Print hierarchy to screen if enabled in config.
	if ( $print_hierarchy_flag eq 'Y' ) {
		print $print_string;
	}
}

# Prints out manager details to the log and to screen (if configured to do so).
# This function was created for cleaner code up top.
sub print_manager_details {
	my $print_string = 	
			"$employees{$employee_id}{FIRST_NAME} "
			. "$employees{$employee_id}{LAST_NAME} "
			. "$employee_id "
			. "($employees{$employee_id}{ROLE} \$$total_allocation_cost)\n";
	if ( $print_hierarchy_flag eq 'Y' ) {
		print 	"Displaying hierarchy tree "
				. "(PRINT_HIERARCHY = 'Y' in config)\n"
				. "Name EmployeeID (Role and Individual Alloc Cost)\n\n";
		print "$print_string";
	}
	print LOG $print_string;
}

# Prints out summary details to the log and to screen (if configured to do so).
# This function was created for cleaner code up top.
sub print_results_to_log {
	print LOG	"$employees{$employee_id}{FIRST_NAME} "
				. "$employees{$employee_id}{LAST_NAME}\n"
				. "Employee ID: $employee_id\n"
				. "Role: $employees{$employee_id}{ROLE}\n"
				. "Department: $employees{$employee_id}{DEPARTMENT}\n"
				. "Total Allocation Cost: \$$total_allocation_cost\n";
}
1;

