#!/bin/perl
use warnings;
use strict;

##############################################################
# Script      : ALLOCATION_CONFIGS.pm (Module)
# Author      : Brad Galyean (bgalyean)
# Date        : 04/28/2016
# Last Edited : 04/28/2016, bgalyean
# Description : required by the monthly allocation scripts. This module
#               loads the settings from the configuration files, checks
#               the settings for errors, and makes the settings available
#               as functions.
##############################################################

package ALLOCATION_CONFIGS;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(get_config get_employee_cost);

my %configurations;
my %allocations;

# Load main configurations from monthly_allocations.cfg
if ( ! open ( CONFIGURATIONS, "../cfg/monthly_allocations.cfg" ) ) {
	die "Could not open monthly_allocations.cfg: $!";
}
while (my $line = <CONFIGURATIONS>) {
	chomp $line;
	# Ignore if line is a comment or does not contain a pipe separator. 
	if (($line !~ /\#/) && ($line =~ /\|/)) {
		my ($setting, $value) =  split(/\|/, $line);
		$configurations{$setting} =  $value;
	}
}
close(CONFIGURATIONS);


# Load the configured allocation costs from cost_allocations.cfg.
if ( ! open ( ALLOCATIONS, "../cfg/cost_allocations.cfg" ) ) {
	die "Could not open cost_allocations.cfg: $!";
}								
while ( my $line = <ALLOCATIONS> ) {
	chomp $line;
	my ( $employee_role, $allocation_amount ) = split ( /\|/ ,$line );
	my $check_amount_message = check_number ( $allocation_amount );
	if ( $check_amount_message eq "Success" ) {
		$allocations{uc($employee_role)} = $allocation_amount;
	}
	else {
		die "cost_allocations.cfg: $employee_role|$allocation_amount "
			. " ($check_amount_message)";
	}

}
close (ALLOCATIONS);


##############################################
### Sub-Functions defined below this line. ###
##############################################

sub get_config { 
   return  $configurations{$_[0]};
}

sub get_employee_cost {
	return  $allocations{$_[0]};
}

sub check_config {
	my @config_settings = (			"ROOT_DIR",
									"EMPLOYEE_DATA_FILE",
									"RUN_SQL",
									"HEADER_CHECK",
									"TRAILER_CHECK",
									"DATE_CHECK",
									"RECORD_COUNT_CHECK",
									"MIN_RECORD_COUNT",
									"MAX_RECORD_COUNT",
									"PRINT_HIERARCHY",
									"1",	# Log severity definition
									"2",	# Log severity definition
									"3",	# Log severity definition
	);
	foreach (@config_settings) {
		if (!get_config( $_ )) {
			die "Configuration setting $_ is missing from config. Add it.";
		}
	}
	return "Success";
}

sub check_number {
	my $original_number = $_[0];
	my $temp_number = $original_number;
	
	# Check if number is all digits.
	$temp_number =~ s/\.//;
	if ( $temp_number !~ /^[\d]+$/ ) {
		return "allocation amount is not a valid number";
	}
	
	# If the number is zero, move on now before checking for cent-fractions.
	if ($original_number == 0 )  {
		return "Success";
	}

	# If there are cents in the value, ensure its 2 digits only.
	if ( $original_number =~ /\./ ) {
		my $cents = $original_number;
		$cents =~ /\.(.*)$/;
		if ( $1 !~ /^\d{2}$/ ) {
			return "cent value not valid";
		}
	}
	
	# Everything checked out ok. 
	return "Success";
}
1;

