#!/usr/bin/perl -w
package Udw_cmds;

use strict;
use lib qw(/sirius/tools/bkscripts);
use Comm;
use Errno qw(EAGAIN);
use Exporter;
use Fcntl;
use File::Basename;
use Misc;
use POSIX qw(sys_wait_h);
use Time::HiRes qw(usleep);

use vars qw(@ISA @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(check_connection reflash get_build_time get_rev_string get_product_name get_target_name get_package_name get_package_rev
	     get_serial_number get_machine_state get_scm_key close_connection turn_on send_cmd cat wait_for_clean_serial wait_for_idle
	     search_usb_devices recover_assert get_num_images safe_reflash get_unit_stats post_reflash_tasks set_job_filters);


my $debug = undef;
#$debug = 1;

### GLOBALS ###
my @JOB_FILTERS = ();

### PROGRAMS ###
my $HPCOREDUMP_RESET = "/sirius/tools/bin/hpcoredump -capture -reset -device ";
my $HPCOREDUMP_REFLASH = "/sirius/tools/bin/hpcoredump -reflash -device ";
my $prompt = "./bin/Popup";
my $usblp_list = "/sirius/tools/bin/usblp list";

### CONSTANTS ###
use constant FALSE => 0;
use constant TRUE => 1;
use constant SUCC => 0;
use constant ERROR => 1;
use constant OFF_STATE => 1;
use constant MFG_OFF_STATE => 2;
use constant IDLE_STATE => 6;
use constant LANGUAGE_REGION_OOBE => 1;
use constant SERIAL_WAIT_TIME_4_POWER_EVENT => 5;
use constant SERIAL_WAIT_TIME_4_REFLASH => 30;
use constant WAIT_TIME_4_IDLE => 20;

### MACHINE STATE CONSTANTS ###
use constant MACHINE_STATES => {
        0 => "INITIALIZING",
        1 => "OFF",
        2 => "MFG_OFF",
        3 => "GOING_ON",
        4 => "IDS_STARTUP_REQUIRED",
        5 => "IDS_STARTUP",
        6 => "IDLE",
        7 => "IO_PRINTING",
        8 => "REPORTS_PRINTING",
        9 => "CANCELING_PRINTING",
        10 => "IO_STALL",
        11 => "DRY_TIME_WAIT",
        12 => "PEN_CHANGE",
        13 => "OUT_OF_PAPER",
        14 => "BANNER_EJECTED_NEEDED",
        15 => "BANNER_MISMATCH",
        16 => "PHOTO_MISMATCH",
        17 => "DUPLEX_MISMATCH",
        18 => "MEDIA_TOO_NARROW",
        19 => "MEDIA_UPSIDE_DOWN",
        20 => "MEDIA_JAM",
        21 => "CARRIAGE_STALL",
        22 => "PAPER_STALL",
        23 => "SERVICE_STALL",
        24 => "PICK_MOTOR_STALL",
        25 => "PUMP_MOTOR_STALL",
        26 => "MOTOR_STALL",
        27 => "PEN_FAILURE",
        28 => "INK_SUPPLY_FAILURE",
        29 => "HARD_ERROR",
        30 => "IDS_HW_FAILURE",
        31 => "POWERING_DOWN",
        32 => "FP_TEST",
        33 => "HYDE_MISSING",
        34 => "OUTPUT_TRAY_CLOSED",
        35 => "DUPLEXER_MISSING",
        36 => "DUPLEXER_INVALID",
        37 => "OUT_OF_INK",
        38 => "MEDIA_SIZE_MISMATCH",
        39 => "ASSERT",
        40 => "LANG_MENU",
        41 => "DC_PRINTING",
        42 => "DC_PRINTING_ABORT_ERROR",
        43 => "DC_SAVING",
        44 => "DC_CANCELING_SAVING",
        45 => "DC_SAVING_ABORT_ERROR",
        46 => "DC_DELETING",
        47 => "DC_CANCELING_DELETING",
        48 => "DC_DELETING_ABORT_ERROR",
        49 => "DC_EMAILING",
        50 => "DC_EMAIL_ABORT_ERROR",
        51 => "DC_CANCELING_EMAILING",
        52 => "DC_CARD_SHORT_ERROR",
        53 => "DC_CARD_REMOVED_ERROR",
        54 => "DC_BUBBLES_SCANNING",
        55 => "DC_BUBBLES_SCAN_DONE",
        56 => "DC_CANCELING_BUBBLES",
        57 => "DC_BUBBLES_ABORT_ERROR",
        58 => "DC_USBHOST_OVERCURRENT_ERROR",
        59 => "DC_VIDEO_ENHANCE_PROCESSING",
        60 => "DC_CANCELING_VIDEO_ENHANCE",
        61 => "DC_VIDEO_ENHANCE_ABORT_ERROR",
        62 => "DC_VIDEO_ENHANCE_DELETE",
        63 => "DC_VIDEO_ENHANCE_ZOOM",
        64 => "DC_VIDEO_ENHANCE_PLAYBACK",
        65 => "DC_REDEYE_PROCESSING",
        66 => "DC_CANCELING_REDEYE",
        67 => "DC_REDEYE_ABORT_ERROR",
        68 => "MEDIA_TOO_WIDE",
        69 => "MEDIA_WRONG",
        70 => "MEDIA_TYPE_WRONG",
        71 => "DOOR_OPEN",
        72 => "PEN_NOT_LATCHED",
        73 => "INK_SUPPLY_CHANGE",
        74 => "GENERIC_ERROR",
        75 => "IDS_STARTUP_BLOCKED_LOI",
        76 => "VLOI",
        77 => "ATTENTION_NEEDED"};

### UDW CONSTANTS ###
use constant REFLASH => "udw.srec_download";
use constant BLD_TIME => "bio.bld_time";
use constant REV_STR => "udw.get_fw_rev";
use constant TARGET => "bio.target";
use constant PRODUCT => "bio.project";
use constant PACKAGE_NAME => "bio.pkg_name";
use constant PACKAGE_PHASE => "bio.pkg_phase";
use constant PACKAGE_REV => "bio.pkg_fw_rev";
use constant SCM_KEY => "bio.scm_key";
use constant SCM_URL => "bio.scm_url";
use constant ON => "sm.on";
use constant OFF => "sm.off";
use constant SET_ENGLISH => "ds2.set 70222 1";
use constant SET_FEMP_OFF => "smgr_init.femp 0";
use constant SOFT_OFF_ENABLE => "smgr_power.soft_off_enable"
use constant SET_USA => "ds2.set 70402 15";
use constant DISABLE_OOBE => "ui.attr_int_set ui_f_sys_attr_oobe_state 1";
use constant DISABLE_ALIGNMENT => "ds2.set 70196 0";
use constant JOB_TRACKING => "sm_dispatch_job track 1";
use constant JOB_TRACKING_FILTER => "sm_dispatch_job filter enable ";
#use constant DISABLE_ALIGNMENT => "firm.set_nvm 1 0x0B00 1";
#use constant DISABLE_ALIGNMENT => "firm.set_ram 1 0x0B00 1";
use constant TIME_SET => "timer.date_set ";
use constant MACHINE_STATE => "ds2.get 65541";
use constant GET_NUM_IMAGES => "ds2.get 66932";
use constant GET_SERIAL_NUMBER => "ds2.get_rec_array_string 66038";
use constant ABORT_PCL_JOB => "pcl.abort_job";
use constant WAKE_UP => "smgr_power.simulate_event 1";

use constant PACKAGE_COMPLETE_OOBE_DSIDS => (
	["DSID_IDS_FIRST_CHARGE_REQUIRED", 0],
	["DSID_INK_SUPPLY_OOBE_COMPLETE", 1],
	["DSID_FM_PEN_STARTUP_STEP", 999],
	["DSID_DPU_OVERRIDE", 0],
	["DSID_PRINTHEAD_CAL_NEEDED", 0],
	["DSID_CAL_OOBE_STATE", 2],
	["DSID_OOBE_STATE", 255]
);

#TODO

sub prep_and_send_fhx($$$$$$;$$$);
sub wait_for_reflash($$$$;$$);
sub wait_for_idle($$$$$$$$);
sub udws($$$$;$$);

sub set_job_filters($)
{
	my $ref = shift @_;
	print("Setting job filters: @{$ref}\n") if($debug);
	@JOB_FILTERS = @{$ref};
}

sub get_unit_stats($$$;$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;

	my ($rev_string, $build_time, $scm_key) = undef;
	my ($result, $cmd, $udw_ret, $out, $assert) = undef;
	my $retries_for_strings = 5;
	my $string_attempts = $retries_for_strings;

	### GET REVISION STRING ###
	while($string_attempts != 0)
        {
		### GET REVISION STRING ###
		($result,$cmd,$udw_ret,$out,$assert) = get_rev_string($wtr,$rdr,$s,$tty_buffer,$tty_output);

		#return if there is a problem with the udw command or the comm in general
		return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

		#if $out is something besides spaces then we're good to continue
		last if($out =~ /\w+/);

		print("  - Could not get revision string, trying again\n") if($debug);
		sleep(5);
	}

	return(ERROR, $cmd, ERROR, "Could not find valid revision string")
	  if(not $out || $out =~ /^\s*$/ || $string_attempts == 0);

	$rev_string = $out;
	print("- Revision string: $rev_string\n") if($debug);
	###########################

	#### BUILD TIME ####
	$string_attempts = $retries_for_strings;
	while($string_attempts != 0)
	{
		### GET BUILD TIME STRING ###
		($result,$cmd,$udw_ret,$out,$assert) = get_build_time($wtr,$rdr,$s,$tty_buffer,$tty_output);

		#return if there is a problem with the udw command or the comm in general
		return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

		#if $out is something besides spaces then we're good to continue
		last if($out =~ /\w+/);

		print("  - Could not get build string, trying again\n") if($debug);
		sleep(5);
	}

	return(ERROR, $cmd, ERROR, "Could not find valid build string")
	  if(not $out || $out =~ /^\s*$/ || $string_attempts == 0);

	$build_time = $out;
	print("- Build time: $build_time\n") if($debug);
	###########################

	#### SCM KEY ####
	$string_attempts = $retries_for_strings;
	while($string_attempts != 0)
	{
		### GET SCM KEY STRING ###
		($result,$cmd,$udw_ret,$out,$assert) = get_scm_key($wtr,$rdr,$s,$tty_buffer,$tty_output);

		#return if there is a problem with the udw command or the comm in general
		return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

		#if $out is something besides spaces then we're good to continue
		last if($out =~ /\w+/);

		print("  - Could not get scm key string, trying again\n") if($debug);
		sleep(5);
	}

	return(ERROR, $cmd, ERROR, "Could not find valid scm key")
	  if(not $out || $out =~ /^\s*$/ || $string_attempts == 0);

	$scm_key = $out;
	print("- SCM Key: $scm_key\n") if($debug);
	###########################

	return(SUCC, "", SUCC, "", undef, $rev_string, $build_time, $scm_key);
}

sub post_reflash_tasks($$$;$$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	my $package = shift @_;

	my ($result,$cmd,$udw_ret,$out,$assert) = undef;

        #Set the language and region if needed
        if(LANGUAGE_REGION_OOBE)
        {
                ($result,$cmd,$udw_ret,$out,$assert) = udws_direct(SET_ENGLISH,$wtr,$rdr,$s,$tty_buffer,$tty_output);
                return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

                ($result,$cmd,$udw_ret,$out,$assert) = udws_direct(SET_USA,$wtr,$rdr,$s,$tty_buffer,$tty_output);
                return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

		if($package)
		{
			foreach(PACKAGE_COMPLETE_OOBE_DSIDS)
			{
				my ($dsid,$value) = @{$_};
				($result,$cmd,$udw_ret,$out,$assert) = udws_direct("ds2.set_by_name $dsid $value",$wtr,$rdr,$s,$tty_buffer,$tty_output);
				return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);
			}
		}
		else
		{
			($result,$cmd,$udw_ret,$out,$assert) = udws_direct(DISABLE_OOBE,$wtr,$rdr,$s,$tty_buffer,$tty_output);
			return($result,$cmd,$udw_ret,$out,$assert) if($assert);

			($result,$cmd,$udw_ret,$out,$assert) = udws_direct(DISABLE_ALIGNMENT,$wtr,$rdr,$s,$tty_buffer,$tty_output);
			return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);
		}
        }

        ## Set the time correctly so dont' have any problems with
        # timestamp on pens
        my @times = localtime(time());
        my $time_str = TIME_SET." $times[0], $times[1], $times[2], $times[3], ".($times[4]+1).", ".($times[5]+1900);
        ($result,$cmd,$udw_ret,$out,$assert) = udws_direct($time_str,$wtr,$rdr,$s,$tty_buffer,$tty_output);
        #return if there is a problem with the udw command or the comm in general
        return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);
        ###########################

	return(SUCC,"",SUCC,"");
}

sub reflash($$$$$;$$$)
{
	my $fhx_file = shift @_;
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $serial_no = shift @_;
	my $package = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;

	my ($result,$cmd,$udw_ret,$out,$assert);

	#make sure file is there
	return(ERROR,REFLASH,ERROR,"Could not find file at $fhx_file") unless(-e "$fhx_file");
	return(ERROR,REFLASH,ERROR,"FHX file $fhx_file is zero length!") if(-z "$fhx_file");

	($result,$cmd,$udw_ret,$out,$assert) = prep_and_send_fhx($fhx_file,$serial_no,$package,$wtr,$rdr,$s,$tty_buffer,$tty_output);
	return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

	($result,$cmd,$udw_ret,$out,$assert) = wait_for_reflash($wtr,$rdr,$s,$package,$tty_buffer,$tty_output);
	return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

	return(SUCC,REFLASH,SUCC,"");
}

sub prep_and_send_fhx($$$$$$;$$$)
{
	my $fhx_file = shift @_;
	my $serial_no = shift @_;
	my $package = shift @_;
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	my $skip_reflash_cmd = shift @_;

	my ($result,$cmd,$udw_ret,$out,$assert);

	unless($skip_reflash_cmd)
	{
		# Workaround for products that do not succesfully go into reflash when asleep
		($result,$cmd,$udw_ret,$out,$assert) = udws_direct(WAKE_UP,$wtr,$rdr,$s,$tty_buffer,$tty_output);
		return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

		($result,$cmd,$udw_ret,$out,$assert) = wait_for_clean_serial(SERIAL_WAIT_TIME_4_POWER_EVENT,$wtr,$rdr,$s,WAKE_UP,$tty_buffer,$tty_output);
		return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

		#turn off femp mode
		($result,$cmd,$udw_ret,$out,$assert) = udws_direct(SET_FEMP_OFF,$wtr,$rdr,$s,$tty_buffer,$tty_output);
		return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

		### REFLASH UNIT ############
		#send the reflash cmd to unit
		($result,$cmd,$udw_ret,$out,$assert) = udws_direct(REFLASH,$wtr,$rdr,$s,$tty_buffer,$tty_output);
		# Temporarily work around assert during reflash where device still goes into reflash mode
		if($package and $assert and $out =~ /Waiting for SREC data/)
		{
			my $assert_output = "";
			foreach(split(/\n/,$out))
			{
				$assert_output .= $_."\n" if($_ =~ /^\*\*\*/);
			}
			print("WARNING: Assert during shutdown to reflash!\n".
			      "$assert_output\n");
		}
		else
		{
			#return if there is a problem with the udw command or the comm in general
			return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);
		}
		print("- Sent reflash command\n") if($debug);
	}

	#wait for no-output
	my $wait_time = ($package) ? (SERIAL_WAIT_TIME_4_REFLASH * 2) : (SERIAL_WAIT_TIME_4_REFLASH);
	($result,$cmd,$udw_ret,$out,$assert) = wait_for_clean_serial($wait_time,$wtr,$rdr,$s,REFLASH,$tty_buffer,$tty_output);
	# Temporarily work around assert during reflash where device still goes into reflash mode
	if($package and $assert and $out =~ /Waiting for SREC data/)
	{
		my $assert_output = "";
		foreach(split(/\n/,$out))
		{
			$assert_output .= $_."\n" if($_ =~ /^\*\*\*/);
		}
		print("WARNING: Assert during shutdown to reflash!\n".
		      "$assert_output\n");
	}
	else
	{
		return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);
	}

	print("WARNING: 'Waiting for SREC data' not seen on serial!\n") unless($out =~ /Waiting for SREC data/);

	#we should not get any output from this command
	($result,$cmd,$udw_ret,$out,$assert) = udws_direct("",$wtr,$rdr,$s,$tty_buffer,$tty_output);
	unless($result == ERROR)
	{
		print("- Printer is still communicating after reflash command!\n");
		return(ERROR,REFLASH,ERROR,"Printer is still available on serial and is NOT in reflash mode!");
	}

	my $usb_port;
        my $search_attempts = 5;
	while($search_attempts > 0)
	{
		$usb_port = search_usb_devices("reflash",$serial_no,undef,TRUE);
		last if($usb_port);
		sleep(5);
	}
	return(ERROR,"Search_usb_devices",ERROR,"Printer not enumerated as 'reflash' on USB") unless($usb_port);

	print("- In reflash mode\n") if($debug);

	$result = cat($fhx_file,undef,$usb_port);
	return(ERROR,"cat",ERROR,"Error sending FHX file") if($result);

	my $done_marker = FALSE;
	sysopen(USBLP,$usb_port,O_RDONLY) or return(ERROR,"Open USBLP",ERROR,"Failed to open $usb_port: $!");
	while(TRUE)
	{
		my $usb_data;
		$result = sysread(USBLP,$usb_data,1024);
		if(not defined($result) or $result == 0)
		{
			if(defined($result) or $! == EAGAIN)
			{
				usleep(2500);
				next;
			}
			print("- Failed to read USB: $!\n");
			last;
		}
		print("Read '$usb_data' from USB\n") if($debug);
		if($usb_data =~ /ZZ;/)
		{
			$done_marker = TRUE;
			last;
		}
	}
	close(USBLP);

	print("WARNING: Did not see reflash completion marker over USB\n") unless($done_marker);

	my $temp_usb = search_usb_devices("reflash",$serial_no,$usb_port,TRUE);
	return(ERROR,REFLASH,ERROR,"Reflash device still present on $usb_port after sending reflash command") if($temp_usb);

	return(SUCC,REFLASH,SUCC,"");
}

sub wait_for_reflash($$$$;$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $wait_extra = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;

	#give it a chance to reflash
	my $wait_time = ($wait_extra) ? (SERIAL_WAIT_TIME_4_REFLASH * 2) : SERIAL_WAIT_TIME_4_REFLASH;
	my ($result,$cmd,$udw_ret,$out,$assert) = wait_for_clean_serial($wait_time,$wtr,$rdr,$s,REFLASH,$tty_buffer,$tty_output);

	if($result == ERROR or $udw_ret == ERROR)
	{
		print("*************\n");
		print("- Error while waiting for reflash. Output: $out\n");
		print("  Will continue to try to wake up unit\n");
		print("*************\n");
	}
	return($result,$cmd,$udw_ret,$out,$assert) if($assert);

	my $after_reflash_attempts = 15;

	while($after_reflash_attempts != 0)
	{
		print("- Are you awake yet?\n") if($debug);

		($result,$cmd,$udw_ret,$out,$assert) = udws_direct("",$wtr,$rdr,$s,$tty_buffer,$tty_output);

		return($result,REFLASH,$udw_ret,$out,$assert) if($assert);

		#great! we're back up!
		last if($result == SUCC and $udw_ret == SUCC);

		#sleep to give the unit chance to reflash
		sleep(10);

		$after_reflash_attempts -= 1;
	}

	#never recovered after reflash
	return(ERROR,REFLASH,$udw_ret,"Could not recover after reflash. Output: $out",$assert) unless($after_reflash_attempts);

	print("- Yes! awake!\n") if($debug);
	return(SUCC,REFLASH,SUCC,"");
}

sub check_connection($$)
{
	my $device = shift @_;
	my $s = shift @_;
	if($device =~ /tty/)
	{
		return(open_tty($device,$s));
	}
	else
	{
		return(open_socket($device,$s));
	}
}

sub get_build_time($$$;$$)
{
	my $wtr= shift @_;
	my $rdr= shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(BLD_TIME,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub get_num_images($$$;$$)
{
	my $wtr= shift @_;
	my $rdr= shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(GET_NUM_IMAGES,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub get_rev_string($$$;$$)
{
	my $wtr= shift @_;
	my $rdr= shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(REV_STR,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub get_product_name($$$;$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(PRODUCT,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub get_target_name($$$;$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(TARGET,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub get_package_name($$$;$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;

	my ($name,$phase);
	my ($result,$cmd,$udw_ret,$assert);
	($result,$cmd,$udw_ret,$name,$assert) = udws_direct(PACKAGE_NAME,$wtr,$rdr,$s,$tty_buffer,$tty_output);
	return ($result,$cmd,$udw_ret,$name,$assert) if($result == ERROR or $udw_ret == ERROR or $name !~ /\w+/ or $name eq "NONE");

	($result,$cmd,$udw_ret,$phase,$assert) = udws_direct(PACKAGE_PHASE,$wtr,$rdr,$s,$tty_buffer,$tty_output);
	return ($result,$cmd,$udw_ret,$phase,$assert) if($result == ERROR or $udw_ret == ERROR or $phase !~ /\w+/);
	return ($result,$cmd,$udw_ret,$name."_".$phase,$assert);
}

sub get_package_rev($$$;$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(PACKAGE_REV,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub get_serial_number($$$;$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(GET_SERIAL_NUMBER,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub get_machine_state($$$;$$)
{
	my $wtr= shift @_;
	my $rdr= shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(MACHINE_STATE,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub get_scm_key($$$;$$)
{
	my $wtr= shift @_;
	my $rdr= shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws_direct(SCM_KEY,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub turn_on($$$;$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws(ON,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub send_cmd($$$$;$$)
{
	my $cmd = shift @_;
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;
	return(udws($cmd,$wtr,$rdr,$s,$tty_buffer,$tty_output));
}

sub close_connection($$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	if(ref($wtr) =~ /Socket/)
	{
		return(close_socket($wtr,undef,$s));
	}
	else
	{
		return(close_tty($wtr,$rdr,$s));
	}
}

sub do_cat($$)
{
	my ($input,$output) = @_;

	my @fstat = stat($input);
	return(ERROR,"Failed to stat $input: $!") unless(@fstat);
	my $input_size = $fstat[7];

	my $basename = File::Basename::basename($input);
	print("- Sending $basename ($input_size bytes) to $output ");

	sysopen(INPUT,$input,O_RDONLY) or return(ERROR,"Failed to open $input: $!");
	unless(sysopen(OUTPUT,$output,O_WRONLY))
	{
		print("\nERROR: Failed to open $output: $!\n");
		close(INPUT);
		return(ERROR);
	}

	my $result;
	my $bytes_written = 0;
	my $total_progress = 0;
	while(TRUE)
	{
		# Read a chunk
		my $data;
		$result = sysread(INPUT,$data,16384);
		unless(defined($result))
		{
			print("\nERROR: Failed to read $input: $!\n");
			close(OUTPUT);
			close(INPUT);
			return(ERROR);
		}
		last if($result == 0);

		# Write a chunk (completely)
		my $bytes_left = length($data);
		while($bytes_left > 0)
		{
			my $offset = length($data) - $bytes_left;
			$result = syswrite(OUTPUT,$data,$bytes_left,$offset);
			unless(defined($result))
			{
				print("\nERROR: Failed to write $output: $!\n");
				close(OUTPUT);
				close(INPUT);
				return(ERROR);
			}
			$bytes_left -= $result;
		}

		# Progress indicator
		$bytes_written += length($data);
		my $progress = ($bytes_written / $input_size) * 100;
		if (($progress - $total_progress) >= 2)
		{
			$total_progress += 2;
			print(".");
		}
	}
	close(INPUT);
	close(OUTPUT);

	print("\n");
	return(SUCC);
}

#PASSED: (<file_to_cat>,$timeout,$usb,[$usb_id])
sub cat($$$;$$)
{
	my ($file,$timeout,$usb,$usb_id,$serial_no) = @_;
	my $ret;

	# if $usb_id is defined then make sure that the correct
	# device is on the usb port before catting
	if($usb_id and $serial_no)
	{
		my $new_usb = search_usb_devices($usb_id,$serial_no);

		if($usb ne $new_usb)
		{
			print("- NOTE: The usb device has switched ports from $usb -> $new_usb\n") if($debug);
		}

		$usb = $new_usb;
	}

	## make sure that USB is defined
	unless($usb)
	{
		print("ERROR: USB device is not defined, so cannot cat to it!\n");
		kill('TERM',$$);
	}

	if($timeout)
	{
		my $child = fork();
		unless(defined($child))
		{
			print("ERROR: Unable to fork child for cat: $!\n");
			return(ERROR);
		}

		if($child)
		{
			my $result;
			while(TRUE)
			{
				$result = waitpid($child,WNOHANG);
				last if($result or not $timeout);
				$timeout--;
				sleep(1);
			}

			if($result)
			{
				$ret = $? >> 8;
			}
			else
			{
				kill('TERM',$child);
				waitpid($child,0);
				print("\n\nERROR: cat timeout, killing process!!\n");
				$ret = ERROR;
			}
		}
		else
		{
			# Turn off warnings for threads due to Perl interpreter bug
			no warnings 'threads';
			$SIG{INT} = 'DEFAULT';
			$SIG{TERM} = 'DEFAULT';
			$ret = do_cat($file,$usb);
			exit($ret);
		}
	}
	else
	{
		$ret = do_cat($file,$usb);
	}

	return $ret;
}

sub wait_for_clean_serial($$$$$;$$)
{
	my ($timeout,$wtr,$rdr,$s,$cmd,$tty_buffer,$tty_output) = @_;
	#return(read_parse_serial($timeout, $wtr,$rdr, $s));
	return(read_parse_serial($wtr,$rdr,$s,$cmd,$timeout,$tty_buffer,$tty_output));
}

sub wait_for_idle($$$$$$$$)
{
	my ($wtr,$rdr,$s,$cmd_in,$timeout,$prod,$tty_buffer,$tty_output) = @_;

	my $max_wait_attempts = 3;
	my $wait_attempts = $max_wait_attempts if($cmd_in =~ ON);

	while(1)
	{
		print(" - Waiting for unit to reach IDLE state\n");

		my ($ret,$cmd,$udw_ret,$out,$assert) = wait_for_clean_serial($timeout,$wtr,$rdr,$s,$cmd_in,$tty_buffer,$tty_output);

		return (ERROR,$assert,$out) if($ret == ERROR or $assert);

		($ret,$cmd,$udw_ret,$out,$assert) = get_machine_state($wtr,$rdr,$s,$tty_buffer,$tty_output);

		if($ret == ERROR or $udw_ret == ERROR)
		{
			print("***WARNING: Error reading the machine's state!\n");
			return (ERROR,$assert,$out);
		}

		return (SUCC,undef,undef) if($out == IDLE_STATE);
		return (SUCC,undef,undef) if(($out == OFF_STATE or $out == MFG_OFF_STATE) and ($cmd_in =~ REFLASH or $cmd_in =~ OFF));

		if($wait_attempts)
		{
			$wait_attempts -= 1;
			next;
		}
		notify_of_printer_state($out,$prod,$cmd_in);
	}
}

sub notify_of_printer_state($$$)
{
	my $printer_state = shift @_;
	my $prod = shift @_;
	my $cmd = shift @_;

	print("\a");
	print("***************************\n");
	print("***************************\n");
	print("Please see pop-up message for prompt\n");
	print("***************************\n");
	print("***************************\n");

	my $state_string = MACHINE_STATES->{$printer_state};
	$state_string = "UNKNOWN" unless($state_string);
	my $prompt_message = "Unit was unable to reach idle state!\n".
			     "Reported state is: $state_string\n".
			     "Please correct the situation and click Continue to resume testing.\n".
			     "[Waiting for idle: $cmd]";

	my ($ret,$out) = command("$prompt 'Automatic Testing Notification for $prod' '$prompt_message'");

	if($ret)
	{
		($ret,$out) = command("$prompt 'Automatic Testing Notification for $prod' 'You clicked Quit/No. Click Quit/No again to exit the current test, ".
				      "or click Continue/Yes to resume testing'");

		kill('TERM',$$) if($ret);
	}

	return;
}

#passed a name and returns the USB device it is on
sub search_usb_devices($$;$$)
{
	my $name = shift @_;
	my $serial_no = shift @_;
	my $usb_port = shift @_;
	my $quiet = shift @_;
	my @matches = ();

	my ($ret,$out) = command_no_error("$usblp_list");
	if($ret)
	{
		print("- Failed to get usblp device list: $out\n");
		return;
	}

	my @lines = split(/\n/,$out);
	foreach my $line (@lines)
	{
		print("- $line\n") if($debug);
		if($line =~ /^(\S+) -> \[.*\] (.*) \((.*)\)$/)
		{
			my ($usb,$mdl,$ser) = ($1,$2,$3);
			next if($usb_port and $usb ne $usb_port);
			next unless($serial_no eq $ser);
			if($mdl =~ /$name/)
			{
				if($mdl =~ /FAX/)
				{
					print("- Ignoring FAX interface for $name on $usb\n") if($debug);
					next;
				}
				push(@matches,$usb);
			}
			else
			{
				print("- WARNING: Found device with serial number $serial_no but model does not match '$name' ($mdl)\n");
			}
		}
		else
		{
			print("- Failed to correctly parse '$line'\n");
		}
	}

	if(scalar(@matches) == 1)
	{
		return(pop(@matches));
	}
	elsif(@matches)
	{
		print("***\n") unless($quiet and not $debug);
		print(" FOUND MORE THAN 1 UNIT ON USB NAMED '$name' with serial number '$serial_no'. CANNOT CONTINUE!\n") unless($quiet and not $debug);
		print("***\n") unless($quiet and not $debug);
		return(undef);
	}
	else
	{
		print("***\n") unless($quiet and not $debug);
		print(" COULD NOT FIND NAME: '$name' with serial number '$serial_no' on USB ports\n") unless($quiet and not $debug);
		print("***\n") unless($quiet and not $debug);
		return(undef);
	}
}

#What to do for an assert?
#	Run hpcoredump on usb
#	upload that file to location X
#
sub recover_assert($$)
{
	my $usb = shift @_;
	my $serial_no = shift @_;

	my $new_usb = search_usb_devices("coredump",$serial_no);

	unless($new_usb)
	{
		print("ERROR: Coredump device not found on USB!\nCannot continue!\n");
		return(ERROR,"Coredump device not found on USB");
	}

	if($usb ne $new_usb)
	{
		print("WARNING: Device has switched from $usb -> $new_usb during assert\n");
		$usb = $new_usb;
	}

	my ($ret,$out) = command("$HPCOREDUMP_RESET $usb");
	return(ERROR,"ERROR running hpcoredump! Error output: $out") if($ret);

	my @coredumps = ($out =~ /^\s*coredump:\s+(.*)\s*$/mg);
	if (@coredumps)
	{
		return(SUCC, \@coredumps);
	}
	else
	{
		return(ERROR, "ERROR trying to parse coredump output: $out\n");
	}
}

# this function is called after an assert has occurred
# hpcordump has already been used and the unit should be
# sitting at ready prompt.
# But to make sure the next test doesn't have the same
# assert we'll reflash to a known good test then continue on.

# the known good fhx will be stored in the $prod directory
# and called $prod.keep

# return ($result,$cmd,$udw_ret,$out,$assert)
sub safe_reflash($$$$$$$;$)
{
	my ($prod,$serial_no,$package,$file,$wtr,$rdr,$s,$tty_buffer) = @_;
	my $usb;

	return(ERROR,"Safe reflash",ERROR,"Could not find the .keep fhx file at $file",FALSE) unless(-e $file);
	return(ERROR,"Safe reflash",ERROR,"The .keep fhx file $file is zero bytes",FALSE) if(-z $file);

	#wait for clean_serial
	my ($result,$cmd,$udw_ret,$out,$assert) = wait_for_clean_serial(SERIAL_WAIT_TIME_4_REFLASH,$wtr,$rdr,$s,"Safe reflash",$tty_buffer);
	if($result == ERROR or $udw_ret == ERROR)
	{
		print("*************\n");
		print("Error while waiting for clean serial in safe_reflash\n");
		print("Will continue and hope unit is ready\n");
		print("*************\n");
	}

	unless($assert)
	{
		print("No assert while waiting for clean serial, will now try to reflash\n") if($debug);

		$usb = search_usb_devices($prod,$serial_no);
		return(ERROR,"Safe reflash",ERROR,"Could not find the product $prod with serial number $serial_no on usb ports",FALSE) unless($usb);

		($result,$cmd,$udw_ret,$out,$assert) = prep_and_send_fhx($file,$serial_no,$package,$wtr,$rdr,$s,$tty_buffer);
		return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

		return(wait_for_reflash($wtr,$rdr,$s,$package,$tty_buffer));
	}

	#the unit asserted again! this time use hpcoredump to go straight into reflash
	#this should get by those pesky boot asserts!
	$usb = search_usb_devices("coredump",$serial_no);
	return(ERROR,"Safe reflash",ERROR,"$prod asserted again during safe reflash, and could not find coredump device after",TRUE) unless($usb);

	($result,$out) = command("$HPCOREDUMP_REFLASH $usb");
	return(ERROR,"Safe reflash",ERROR,"Error running hpcoredump! Error output: $out") if($result);

	($result,$cmd,$udw_ret,$out,$assert) = wait_for_clean_serial(SERIAL_WAIT_TIME_4_REFLASH,$wtr,$rdr,$s,REFLASH,$tty_buffer);
	if($result == ERROR or $udw_ret == ERROR)
	{
		print("*************\n");
		print("Error while waiting for clean serial in safe_reflash\n");
		print("Will continue if unit is in reflash mode\n");
		print("*************\n");
	}
	return(ERROR,"Safe reflash",ERROR,"Unit asserted again",TRUE) if($assert);

	$usb = search_usb_devices("reflash",$serial_no);
	return(ERROR,"Safe reflash",ERROR,"Could not find unit in reflash mode with serial number $serial_no on USB ports",FALSE) unless($usb);

	($result,$cmd,$udw_ret,$out,$assert) = prep_and_send_fhx($file,$serial_no,$package,$wtr,$rdr,$s,$tty_buffer);
	return($result,$cmd,$udw_ret,$out,$assert) if($result == ERROR or $udw_ret == ERROR);

	return(wait_for_reflash($wtr,$rdr,$s,$package,$tty_buffer));
}

sub udws($$$$;$$)
{
	my $cmd = shift @_;
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s = shift @_;
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;

	#Turn on Job tracking
	my ($result,$error_cmd,$udw_ret,$out,$assert);
	udws_direct(JOB_TRACKING,$wtr,$rdr,$s,$tty_buffer,$tty_output);
	#don't check output.. just continue on because $cmd might be expecting an error
	#like when we are waiting for unit to go into reflash mode (srec download)

	#Filter out jobs we don't care about
	foreach (@JOB_FILTERS)
	{
		udws_direct(JOB_TRACKING_FILTER.$_,$wtr,$rdr,$s,$tty_buffer,$tty_output);
	}

	#pass and return
	($result,$error_cmd,$udw_ret,$out,$assert) = udws_direct($cmd,$wtr,$rdr,$s,$tty_buffer,$tty_output);

	return($result,$error_cmd,$udw_ret,$out,$assert);
}

1;
