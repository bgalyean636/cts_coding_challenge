#!/bin/perl
use warnings;
use strict;
use Time::Piece;
use File::FindLib 'lib';
use ALLOCATION_CONFIGS;

##############################################################
# Script      : data_check.pl
# Author      : Brad Galyean (bgalyean)
# Date        : 05/01/2016
# Last Edited : 05/01/2016, bgalyean
# Description : called by monthly allocation script. Checks the data contained
#               within the employee data file for header/trailer, date, counts,
#               data correctness. Various checks can be turned on/off within
#               the monthly allocations config. 
##############################################################

# Pre-define important variables.
my $data_file = get_config( "ROOT_DIR" ) . get_config( "EMPLOYEE_DATA_FILE" );
my $header_check_flag = get_config( "HEADER_CHECK" );
my $trailer_check_flag = get_config( "TRAILER_CHECK" );
my $date_check_flag = get_config( "DATE_CHECK" );
my $record_check_flag = get_config( "RECORD_COUNT_CHECK" );
my $minimum_record_count = get_config( "MIN_RECORD_COUNT" );
my $maximum_record_count = get_config( "MAX_RECORD_COUNT" );
my $current_date = localtime->strftime( '%Y%m%d' );


# Check the data file exists, and attempt to open for reading.
if ( ! open (EMPLOYEE_DATA, "$data_file" ) ) {
	return "Could not open $data_file: $!";
}


########################################################################
# Gather needed stats/info from data, check data for obvious problems. #
########################################################################

# $line_count is used later to verify the footer is the last line in data. 
my $line_count = 0;
# Tracks number of actual data records, header and footer are excluded.
my $total_record_count = 0;
# This hash will keep track of header/footer details.
my %header_footer_info;

while ( my $line = <EMPLOYEE_DATA> ) {
	$line_count++;
	chomp $line;
	my @TEMP_DATA = split ( /\|/, $line );
	
	# Gather info about the header.
	if ( $line =~ /^\#HEADER/ ){
		$header_footer_info{"HEADER_DATE"} = $TEMP_DATA[1];
		$header_footer_info{"HEADER_LINE_NUMBER"} = $line_count;
		$header_footer_info{"HEADER_COUNT"}++;
	}
	
	# Gather info about the trailer.
	elsif ( $line =~ /^\#TRAILER/ ){
		$header_footer_info{"TRLR_TOTAL_RECORDS"} = $TEMP_DATA[1];
		$header_footer_info{"TRLR_LINE_NUMBER"} = $line_count;
		$header_footer_info{"TRLR_COUNT"}++;
	}
	
	# Check that all fields are present and contain data.
	else {
		# Employee ID field must be 6 digits.
		if ( ( !$TEMP_DATA[0] ) || ( $TEMP_DATA[0] !~ /^\d{6}$/ ) ) {
			return ( 	"Error in data on line $line_count of $data_file. "
						. "Employee ID is not 6 digits. ($line)" 
					);
		}
		# Check first, last names, and organization are all present.
		if ( 	( !$TEMP_DATA[1] ) ||
				( !$TEMP_DATA[2] ) ||
				( !$TEMP_DATA[3] )
			) {
			return ( 	"Error in data on line $line_count of $data_file. "
						. "Field(s) are empty. ($line)" 
					);
		}
		
		# Manager field must be 6 digits.
		if ( ( !$TEMP_DATA[5] ) || ( $TEMP_DATA[5] !~ /^\d{6}$/ ) ) {
			return ( 	"Error in data on line $line_count of $data_file. "
						. "Manager is not 6 digits. ($line)" 
					);
		}
		# Increase total if record looks fine.
		$total_record_count++;
	}
}
close(EMPLOYEE_DATA);


#################################################
# Begin checks per configuration file settings. #
#################################################

# MIN_RECORD_COUNT
if ( $line_count < $minimum_record_count ) {
	return ( 	"Number of records ($total_record_count) is less than the "
				. "configured MIN_RECORD_COUNT ($minimum_record_count)." 
			);
}
# MAX_RECORD_COUNT
if ( $line_count > $maximum_record_count ) {
	return ( 	"Number of records ($total_record_count) is more than the "
				. "configured MAX_RECORD_COUNT ($maximum_record_count)." 
			);
}
# HEADER_CHECK 
if ( $header_check_flag eq 'Y' ){
	# Does header record exist?
	if ( !$header_footer_info{"HEADER_COUNT"} ) {
		return ( "Header record not found in $data_file." );
	}
	# Are there multiple headers?
	if ( $header_footer_info{"HEADER_COUNT"} > 1 ) {
		return ( "Multiple header records found in $data_file." );
	}
	# Is the header the first line of the file?
	if ( $header_footer_info{"HEADER_LINE_NUMBER"} != 1 ) {
		return ( 	"Header record found on "
					. $header_footer_info{"HEADER_LINE_NUMBER"}
					. ". Header should be first record." 
				);
	}
	# Confirm date on file matches today's date. 
	if ( $date_check_flag eq 'Y' ) {
		if ( !$header_footer_info{"HEADER_DATE"} ) {
			return ( "Date missing from header in $data_file." );
		}
		if ( $header_footer_info{"HEADER_DATE"} != $current_date ) {
			return ( 	"Header date does not match current date"
						. " in  $data_file." 
					);
		}
	}
}

# TRAILER_CHECK (multiple types of checks)
if ( $trailer_check_flag eq 'Y' ) {
	# Was a trailer found? 
	if ( !$header_footer_info{"TRLR_COUNT"} ) {
		return ( "Trailer record not found in $data_file." );
	}
	# Was only one trailer record found?
	if ( $header_footer_info{"TRLR_COUNT"} != 1 ) {
		return ( "Multiple trailer records found in $data_file." );
	}
	# Was trailer the last line of the data file?
	if ( $line_count != $header_footer_info{"TRLR_LINE_NUMBER"} ) {
		return ( 	"Trailer record found on "
					. $header_footer_info{"TRLR_LINE_NUMBER"}
					. ". Trailer should be last record." 
				);	
	}
	# Does the number of data records match the total provided in the trailer?
	if ( $record_check_flag eq 'Y' ) {
		if ( 	$total_record_count != 
				$header_footer_info{"TRLR_TOTAL_RECORDS"} ) {
			return ( 	"Number of data records in $data_file "
						. "($total_record_count) does not match "
						. "the expected total of ("
						. $header_footer_info{"TRLR_TOTAL_RECORDS"}
						. ") provided in the trailer record."
					);
		}
	}
}


# If everything checked out ok, return success message back to main script.
return ( "Success" );




