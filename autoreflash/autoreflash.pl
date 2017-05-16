#!/usr/bin/perl -w
use strict;
#use diagnostics;
use lib qw(./ /sirius/tools/bkscripts);
use JSON;
use SiriusHub;
use Udw_cmds;
use Fcntl;
use IO::File;
use IO::Select;
use Misc;
use File::Basename;
use POSIX qw(strftime uname);
use Socket qw(AF_INET);
use Cwd;
use LWP::UserAgent;
use threads;
use threads::shared;
use Thread::Semaphore;

my $debug = undef;
#$debug = 1;

######################################
#    TODO
#
# + Find a way to set the speed on serial ports. Right now just hoping kermit does that for us
#   looks like POSIX::Termios doesn't support 115200, so might be stuck using kermit to do it for us...
# + Settings file
# + Need to add command in udw file for 'reflash' keyword.
# + On an assert, once we get information, shell out to '/sirius/tools/bin/hpcoredump -capture -device $usb -reset'
#   to recover.
# + Download most recent untested fhx file from server
# + Record that the test has been started (fill out testRequested field)
# + (VOID- We want the autotests to be seperate from the regular tests) Need to have a 'Tester Name'
#   to fill in too.. Maybe for right now just use a standard name (AUTO-TESTER) or something
# + Pause and Stop file
# + prompt option in tests file
# + Remove the first reflash procedure
# - (VOID-Too hard to create) Use a .ful instead of .fhx file for reflash
# - Add LANGUAGE_REGION_OOBE to settings file
# + set date/time after reflash
# + added time before and after reflash so we could keep tabs on how long it's taking
# + wait_after_cmd and wait_time are params in settings file
# + Performance stats on each command, each reflash, etc. etc. (maybe 'report' so can be entered in siriusdb)
# + Keep a limited number of .fhx files (order them when renaming?)
# + Autopopulate comments etc. field of browser window
# + Need to parse the button table so can use button press ID's
# + Have only one unit at a time in reflash mode. They can switch USB ports
#   and all the names are only 'reflash'. Sucks, but don't see another way..
# + Add assert parser to wait function... Stop wait when assert happends!
# + Died in add_test_requested_time returned false
# + lock file in $prod directory to prevent multiple instances per product
# + Create the test_info.html file as the tests are executed, so if have a problem can open it again
# + Easy test submit.. 'Was dash tests OK?'
# + Two units called 'coredump' at same time, hpcoredump might download wrong one. Test for this and exit
# + problem with submitting forms when not autosubmitting. Think we have it as good as can be. need super BKDB!
# + Added job tracking while wait_for_clean_serial is working
# - when using .fhx from directory doesn't pause and ask you to continue before trying to download again.
#   maybe could remove prompt after 'report' then count on a prompt at end of tests file
# + Verify presense of photo card before photo print to avoid false assert (0x020d0f83, 525:lib_pathname.c)
# + Check unit is in idle state before sending commands
# + safe reflash
# + Username needs to be a variable instead of always Autotest
# + Need to make sure that anything returning in after error in reflash releases locks on files
#######################################

#FLUSH STDOUT FILEHANDLE
$| = 1;

### GLOBALS ###
my $base_config_dir = "./config_dir";
my $base_bin_dir = "./bin";
my $coredump_dir_name = "coredump_dir";
my $base_picture_dir = "./config_dir/picture_dir";
my $test_info_file_name = "test_info.html";
my $xterm = "/usr/bin/xterm";
my @xterm_log_args = qw(-font -*-fixed-medium-r-*-*-18-*-*-*-*-*-iso8859-* -geometry 70x24);
my @xterm_serial_args = qw(-sl 8192);
my @xterm_pkg_serial_args = qw(-sl 32768 -geometry 140x40);
my $awk = "/usr/bin/awk";
my $cat = "/bin/cat";
my $grep = "/bin/grep ";
my $ps = "/bin/ps -eo pid,cmd | $grep -v /bin/ps | $grep -v $grep";
my $tail = "/usr/bin/tail -f ";
my $mv = "/bin/mv -f";
my $mkfifo = "/usr/bin/mkfifo";
my $prompt = "$base_bin_dir/Popup";

### FUNCTIONS ###
sub run_autotest($);
sub my_exit($$$$);
sub create_single_fhx($$);
sub construct_fhx_location($);
sub download_file($$$);
sub download_fhx($$);
sub prompt($;$$$$$);
sub load_settings();
sub construct_server_path($);
sub generate_coredump_info($);
sub create_test_file($;$);
sub reflash_good_code($$$$$$$$$);
sub move_fhx_files($);
sub record_test_info($);
sub load_test_info($);
sub submit_results($$$$$$$;$$$);
sub check_test_time($$$);
sub create_pipe($);
sub launch_xterm;
sub sol_tty_mux;

my @reader_threads = ();
my @tty_buffer :shared = ();
my @tty_mux_buffer :shared = ();

# tty_device will be the TTY character device (e.g. /dev/ttyS0)
my $tty_device = undef;

# test_info will keep track of the current build being tested
#  tipKey = tip key of build
#  product = product name
#  build_tag = build_tag
#  build_id = Which build we are testing
#  hw_test_id = Which hw_test we are testing/reporting on
#  branch = branch name
#  targets = Array of build targets (hashes) to load on this unit
#  build_location = where got build from
#  failed = array of udw commands that failed
#  passed = array of udw commands that completed
my %test_info = ();

### CONSTANTS ###
use constant ERROR => 1;
use constant SUCC => 0;
use constant TRUE => 1;
use constant FALSE => 0;
use constant REFLASH_DONE_MARKER => qr/\[FLASH\] Board may now be turned off/;

### DEFAULT SETTINGS FOR SETTINGS FILE VARIABLES ###
  # How many times you search for the file containing tests to run. Set to -1 to try forever.
my $TEST_FILE_ATTEMPTS = 1;
  # If you encounter an error when executing a command, should you quit? Set to 0 to continue after error.
my $QUIT_AFTER_ERROR = 1;
  # If I can't find an .fhx file in the config directory, I will query SiriusDB. Set to 0 to disable and place .fhx files manually.
my $ATTEMPT_FHX_DOWNLOAD = 1;
  # After a reflash has taken place the file can either be moved or removed. Set to 0 to move the old fhx files.
my $REMOVE_FHX_AFTER_REFLASH = 0;
  #how long we will wait for a unit to accept a picture file over USB
my $USB_WAIT_TIMEOUT = 30;
  #how long should we wait before calling the serial line clean
my $WAIT_TIME = 30;
  # Should we always attempt a safe_reflash after an assert?
my $ALWAYS_SAFE_REFLASH = 0;
  # How many times to try each test before giving up
my $TEST_ATTEMPTS = 3;
  # Which job SUIDs to filter out from job tracking
my @JOB_FILTERS = ();
  #which units are attached to which product ID's
#my %mappings = ();
  #which TTY devices are mapped to which code image
#my %tty_mappings = ();
my %additional_ttys = ();
my $pkg_dir = undef;
my $pidFile = undef;
my $product_id = undef;
my $product_serial_number = undef;
my $unique_name = undef;
  #where the coredump files will be placed
my $SERVER_PATH = undef;
my $SERVER = undef;
my $SIRIUS_HUB_USER_EMAIL = undef;

my %commands = ();

  # forked processes
my @children = ();

#####################################################

if(scalar(@ARGV) < 5)
{
  print "Usage: $0 <package_dir> <pidFile> <product_id> <product_serial_num> <default_tty> [[TTY] [TTY] ..]\n";
  exit(1);
}

$pkg_dir = shift(@ARGV);
if(#$pkg_dir not exists){
  print "Package directory `$pkg_dir` does not exists!\n";
  exit(1);
}

$pidFile = shift(@ARGV);
if(#$pidFile not exists){
  print "Product PID file `$pidFile` does not exist!\n";
  exit(1); 
}

$product_id = shift(@ARGV);
$product_serial_number = shift(@ARGV);
$unique_name = $product_id-$product_serial_number;


$tty_device = shift(@ARGV);
if($tty_device !~ /^\/dev\/tty(?:S|USB)\d+$/){
  print "Invalid TTY device name! - expecting `/dev/ttyUSB#` or `/dev/ttyS#`.\n";
  exit(1);
}

# Any more tty devices?
if (scalar(@ARGV) > 0){
  foreach(@ARGV){
    if($_ !~ /^\w+:\/dev\/tty(?:S|USB)\d+$/){
      print "Invalid TTY device and name! - expecting: `label:/dev/ttyUSB#` or `label:/dev/ttyS#`.\n";
      exit(1);
    }
    my $t_tty = split(/:/, $_);
    %additional_ttys{lc$t_tty[0]} = $t_tty[1];
  }
}

# Set up time to stop script, if supplied
#my @end_time = ();
#my @cur_time = ();
#my $cur_time_has_wrapped = undef;
#if(@ARGV)
#{
#  my $time = shift(@ARGV);
#  if($time !~ /^\d{1,2}:\d\d$/)
#  {
#    print "Invalid time specifier!\n";
#    exit(1);
#  }

 # @end_time = split(/:/, $time);
 # @cur_time = localtime(time);
 # if ($end_time[0] < $cur_time[2])
 # {
 #   $cur_time_has_wrapped = 0;
 # }
 # elsif ($end_time[0] == $cur_time[2])
 # {
 #   if ($end_time[1] <= $cur_time[1])
 #   {
 #     $cur_time_has_wrapped = 0;
 #   }
 # }
#}

load_settings();

# We are going to require the AUTOTEST user to be defined in the config file
#unless($SIRIUS_HUB_USER_EMAIL)
#{
#  print(" - You first must define the 'SIRIUS_HUB_USER_EMAIL' variable in your settings file.\n");
#  exit(1);
#}

#unless(%mappings)
#{
#  print(" - You must define the mappings in the mappings file.\n");
#  exit(1);
#}

### CHECK FOR RUNNING KERMIT PROCESSES ###
my @pids = `$ps | $grep kermit`;
if(@pids)
{
  print("- WARNING - You currently have a kermit process running. This might interfere with this script. Please kill the process before running.\n");
  exit(1);
}

# Give the Udw_cmds module the jobs to filter
Udw_cmds::set_job_filters(\@JOB_FILTERS);

run_autotest($tty_device);

sub run_autotest($)
{
  my $tty = shift @_;
  my $usb = undef;

  print ("- Please wait while $tty is scanned for a device\n");

  my $s = IO::Select -> new();

  print("- Testing $tty for connection\n") if($debug);
  my ($ret,$out,$wtr,$rdr) = check_connection($tty,\$s);

  if($ret)
  {
    print("- No device found on $tty\n") if($debug);
    print("  - Could not open device on $tty. Error output: $out\n") if($out and $debug);
    close_connection($wtr,$rdr,\$s);
    die("* Could not find connected device!\n");
  }

  #find the product/package name for this serial device
  my ($product,$package);
  print("- Attempting to get package name from device\n") if($debug);
  my ($result,$cmd,$udw_ret,$assert);
  ($result,$cmd,$udw_ret,$out,$assert) = get_package_name($wtr,$rdr,\$s);

  if($result == ERROR or $udw_ret == ERROR)
  {
    close_connection($wtr,$rdr,\$s);
    if($out =~ /bad command/)
    {
      die("* Device FW is too old, does not support bio commands for packages\n");
    }
    elsif($out =~ /don't understand/)
    {
      die("* Device FW is too old, does not support ludw() function\n");
    }
    else
    {
      die("* Device found on $tty, but could not obtain package name: $out\n");
    }
  }

  unless($out =~ /\w+/)
  {
    close_connection($wtr,$rdr,\$s);
    die("* Package name returned from serial did not contain any word characters: $out\n");
  }

  if($out eq "NONE")
  {
    print("  - Device is not a packaged product, getting product name instead\n") if($debug);
    ($result,$cmd,$udw_ret,$out,$assert) = get_product_name($wtr,$rdr,\$s);
    if($result == ERROR or $udw_ret == ERROR)
    {
      close_connection($wtr,$rdr,\$s);
      die("* Device found on $tty, but could not obtain product name: $out\n");
    }

    unless($out =~ /\w+/)
    {
      close_connection($wtr,$rdr,\$s);
      die("* Product name returned from serial did not contain any word characters: $out\n");
    }

    $product = $out;
    $package = FALSE;
  }
  else
  {
    $product = $out;
    $package = TRUE;
  }

  #find the serial number of this serial device
  my $serial_no;
  print("- Attempting to get serial number name from device\n") if($debug);
  ($result,$cmd,$udw_ret,$serial_no,$assert) = get_serial_number($wtr,$rdr,\$s);

  if($result == ERROR or $udw_ret == ERROR)
  {
    close_connection($wtr,$rdr,\$s);
    die("* Device found on $tty, but could not obtain serial number: $out\n");
  }

  unless($serial_no =~ /\w+/)
  {
    close_connection($wtr,$rdr,\$s);
    die("* Serial number returned from serial did not contain any word characters: $serial_no\n");
  }

  #tell user we found something on this serial
  print("  - Found $product on $tty ($serial_no)\n");
  unless($serial_no == $product_serial_number){
    die("* Serial number detect does not match expected value. ($product_serial_number != $serial_no)\n");
  }

  $usb = search_usb_devices($product_id, $serial_no);
  unless($usb)
  {
    close_connection($wtr,$rdr,\$s);
    die("* Could not find $product (mapped to $mappings{$product} <-> $serial_no) on USB\n");
  }

  #This directory should already exist.
  mkdir("$pkg_dir") unless(-d "$pkg_dir");

  # Create and check the .pid file so we know if a process is running for this product already!
  if(-e "$pidFile")
  {
    open(PID, "$pidFile") or die("Cannot open the pid file at $pidFile: $!\n");
    my @pids = <PID>;
    close(PID);

    if(@pids)
    {
      chomp($pids[0]);
      my ($ret,$out) = command("$ps | $grep 'perl' | $grep 'autoreflash.pl' | grep '$pids[0]'");

      #Found PID.. still running
      unless($ret)
      {
        print("Found PID: $pids[0] still running. Only one instance of scripts can run per product\n");
        print("PID RUNNING: $out\n");
        my_exit(1,$wtr,$rdr,\$s);
      }
    }
  }

  my $tty_pipe = "$pkg_dir/$unique_name.pipe";
  create_pipe($tty_pipe);

  my ($tty_mux_in_pipe,$tty_mux_out_pipe,$tty_mux_fh);
  if($package)
  {
    $tty_mux_in_pipe = "$pkg_dir/$unique_name"."_tty_mux_in.pipe";
    $tty_mux_out_pipe = "$pkg_dir/$unique_name"."_tty_mux_out.pipe";
    create_pipe($tty_mux_in_pipe);
    create_pipe($tty_mux_out_pipe);
  }


  #write the current process into .pid file
  open(PID, ">$pidFile") or die("Cannot open the pid file at $pidFile: $!\n");
  print PID ("$$");
  close(PID);

  if($package)
  {
    close_connection($wtr,$rdr,\$s);
    my %tty_mux_args = ("engine" => "--engine-tty"
                       ,"kernel" => "--kernel-tty"
                       ,"sol"    => "--sol-tty");
    my @sol_tty_args = ();
    # Check each given TTY device and build sol_tty_mux arguments
    foreach(keys(%additional_ttys))
    {
      next if ($_ eq "kernel"); # Hacky
      my $xtty_name = $_;
      print("- Scanning %additional_ttys{$xtty_name}\n");
      ($ret,$out,$wtr,$rdr) = check_connection(%additional_ttys{$xtty_name},\$s);
      if($ret)
      {
        print("- Device not found on %additional_ttys{$xtty_name}\n") if($debug);
        print("  - Could not open TTY device on %additional_ttys{$xtty_name}. Error output: $out\n") if($out and $debug);
        my_exit(1,$wtr,$rdr,\$s);
      }
      ($result,$cmd,$udw_ret,$out,$assert) = get_package_name($wtr,$rdr,\$s);
      if($result == ERROR or $udw_ret == ERROR)
      {
        print("- Error getting package name from %additional_ttys{$xtty_name}\n");
        my_exit(1,$wtr,$rdr,\$s);
      }
      if($out ne $product)
      {
        print("- Package name $out obtained from %additional_ttys{$xtty_name} does not match $product obtained from $tty\n");
        my_exit(1,$wtr,$rdr,\$s);
      }
      close_connection($wtr,$rdr,\$s);
      if (exists %tty_mux_args{$xtty_name}){
        push(@sol_tty_args, %tty_mux_args{$xtty_name}, %additional_ttys{$xtty_name});
      }
    }

    # Open input pipe now so sol_tty_mux doesn't block on startup
    $tty_mux_fh = IO::File -> new();
    sysopen($tty_mux_fh,$tty_mux_in_pipe,O_RDONLY|O_NONBLOCK) or die("Unable to open tty mux input pipe: $!\n");

    my $tty_socket = "$pkg_dir/$unique_name"."_sox.sock";
    my $tty_mux_err = "$pkg_dir/$unique_name"."_tty_mux.err";
    push(@sol_tty_args, "--sox-tty", $tty, "--sox-socket",$tty_socket);
    sol_tty_mux($tty_mux_in_pipe,$tty_mux_err,@sol_tty_args) or die("Failed to launch sol_tty_mux\n");

    #turn on the xterm for the SoX serial pipe
    launch_xterm(@xterm_serial_args,"-T","$product SoX serial output","-e","cat",$tty_pipe) or die("Failed to start xterm for serial window\n");

    #turn on the xterm for the combined serial output
    launch_xterm(@xterm_pkg_serial_args,"-T","$product combined serial output","-e","cat",$tty_mux_out_pipe) or die("Failed to start xterm for combined serial window\n");

    sleep(1);

    unless(-e $tty_socket and -S $tty_socket)
    {
      print("- Failed to find TTY socket at $tty_socket\n");
      close($tty_mux_fh);
      my_exit(1,undef,undef,undef);
    }
    ($ret,$out,$wtr,$rdr) = check_connection($tty_socket,\$s);
    if($ret)
    {
      print("- Device not found on $tty_socket\n") if($debug);
      print("  - Could not open TTY socket device on $tty_socket. Error output: $out\n") if($out and $debug);
      close($tty_mux_fh);
      my_exit(1,$wtr,$rdr,\$s);
    }
  }
  else
  {
    #turn on the xterm for the serial pipe
    launch_xterm(@xterm_serial_args,"-T","$product serial output","-e","cat",$tty_pipe);
  }

  open(STDOUT, ">>$pkg_dir/$unique_name.log") or die("Could not open log file at: $pkg_dir/$unique_name.log: $!\n");
  open(STDERR, ">&STDOUT");
  $| = 1;

  #print some testing header
  print("\n\n\n\n\n\n\n\n\n\n");
  my $time = localtime();
  print("-------- Starting $time ---------\n");

  #Turn on the xterm for the log file:
  launch_xterm(@xterm_log_args,"-T","$product log","-e","$tail $pkg_dir/$unique_name.log");

  print("Creating reader thread...\n") if($debug);
  my $start_sem = Thread::Semaphore -> new(0);
  my $reader_thread = threads -> create(\&tty_reader,$rdr,$start_sem,$tty_pipe,\@tty_buffer);
  die("Could not create thread to read serial output!\n") unless($reader_thread);

  # Wait until reader thread signals it has started
  $start_sem -> down(1);

  push(@reader_threads, $reader_thread);

  if($package)
  {
    print("Creating tty_mux reader thread...\n") if($debug);
    my $mux_start_sem = Thread::Semaphore -> new(0);
    my $mux_reader_thread = threads -> create(\&tty_reader,$tty_mux_fh,$mux_start_sem,$tty_mux_out_pipe,\@tty_mux_buffer);

    die("Could not create thread to read muxed serial output!\n") unless($mux_reader_thread);

    # Wait until reader thread signals it has started
    $mux_start_sem -> down(1);

    push(@reader_threads, $mux_reader_thread);
  }

  # Install signal handler for graceful shutdown
  my $sighandler = sub { my_exit(1,$wtr,$rdr,\$s) };
  $SIG{INT} = \&{$sighandler};
  $SIG{KILL} = \&{$sighandler};

  #keep testing until we hit an error!
  while(TRUE)
  {
    {
      lock(@tty_buffer);
      @tty_buffer = ();
    }
    my $tty_output = "";

    if($package)
    {
      lock(@tty_mux_buffer);
      @tty_mux_buffer = ();
    };

    # if end time was specified, make sure it hasn't passed before beginning next loop
    check_test_time($wtr,$rdr,\$s);

    # pretest - Make sure unit is in a happy state.
    my ($ret,$cmd,$udw_ret,$out,$assert) = get_machine_state($wtr,$rdr,\$s,\@tty_buffer,\$tty_output);
    if($ret == ERROR or $udw_ret == ERROR)
    {
      prompt("Error reading printer state during pretest. Please check all connections to printer.",$product,$wtr,$rdr,\$s,FALSE);
      print("\nPlease restart the script when the issue has been resolved.\nBye!\n");
      my_exit(1,$wtr,$rdr,\$s);
    }
    if($out)
    {
      my $state = Udw_cmds::MACHINE_STATES->{$out};
      $state = "UNKNOWN" unless($state);

      if($state eq "IDLE")
      {
        print "- Beginning test in IDLE\n" if ($debug);
      }
      else
      {
        prompt("WARNING: Printer is not in an IDLE state. The printer must be IDLE before starting testing. ".
               "The current state is reported as '$state'. ".
               "Check that it is not currently processing a job and that all doors/lids are closed.",$product,$wtr,$rdr,\$s,FALSE);
        print("\nPlease restart the script when the issue has been resolved.\nBye!\n");
        my_exit(1,$wtr,$rdr,\$s);
      }
    }
    else
    {
      prompt("WARNING: Printer state was not reported by unit. Please check all connections to printer.",$product,$wtr,$rdr,\$s,FALSE);
      print("\nPlease restart the script when the issue has been resolved.\nBye!\n");
      my_exit(1,$wtr,$rdr,\$s);
    }

    #validate pressence of photocards
    my $num_images;
    ($ret,$cmd,$udw_ret,$num_images,$assert) = get_num_images($wtr,$rdr,\$s,\@tty_buffer,\$tty_output);
    if($ret == ERROR or $udw_ret == ERROR)
    {
      prompt("Error reading number of photos on memory card during pretest. Please check all connections to printer.",$product,$wtr,$rdr,\$s);
      print("\nPlease restart the script when the issue has been resolved.\nBye!\n");
      my_exit(1,$wtr,$rdr,\$s);
    }
    if($num_images == 0)
    {
      print "- Warning, no valid photos found on a photo card\n";
    }
    elsif($num_images != 0)
    {
      print "- $num_images images found on photo card\n" if ($debug);
    }
    else
    {
      prompt("WARNING: Number of images was not reported by unit. Please check all connections to printer.",$product,$wtr,$rdr,\$s,FALSE);
      print("\nPlease restart the script when the issue has been resolved.\nBye!\n");
      my_exit(1,$wtr,$rdr,\$s);
    }

    print "\n";

    my $test_file_attempts = $TEST_FILE_ATTEMPTS;

    ### FIND A TEST LIST
    while($test_file_attempts != 0)
    {
      check_test_time($wtr,$rdr,\$s);

      unless(-r "$pkg_dir/tests")
      {
        print("***************************\n");
        print(" Could not find a testing file in $pkg_dir/tests\n");
        print(" I will sleep for 1 minute then check again.\n");
        print("***************************\n");
        sleep(60);

        $test_file_attempts -= 1;
      }
      else
      {
        last;
      }
    }

    if($test_file_attempts == 0)
    {
      print("Could not find the tests file at: $pkg_dir/tests.\nBye!\n");
      my_exit(1,$wtr,$rdr,\$s);
    }

    open(TESTS,"$pkg_dir/tests") or die("Thought we had the file at $pkg_dir/tests, but couldn't open file: $!\n");
    my @tmp = <TESTS>;
    close(TESTS);

    #take out comments
    my @lines = grep(!/^\s*#/,@tmp);
    chomp(@lines);

    TEST_LOOP: for my $cmd (@lines)
    {
      #strip off leading and trailing whitespace
      $cmd =~ s/^\s*//;
      $cmd =~ s/\s*$//;

      next unless($cmd);

      my $op = undef;
      my $op_ret = SUCC;
      my $op_udw_ret = undef;
      my $op_out = undef;
      my $cmd_start = time();

      ### CHECK FOR STOP OR PAUSE FILES
      # need to some how predeterming stop/pause filenames. CLI parameter?
      if(-e "$pkg_dir/stop")
      {
        unlink("$pkg_dir/stop");
        print("***************************\n");
        print("- Detected a stop file at $pkg_dir/stop\n");
        print("  Removing file and exiting\n");
        print("***************************\n");
        my_exit(0,$wtr,$rdr,\$s);
      }
      elsif(-e "$pkg_dir/pause")
      {
        unlink("$pkg_dir/pause");
        print("- Detected a pause file at $pkg_dir/pause\n");
        print("  Removing file and sleeping for 2 minutes\n");
        sleep(120);
        prompt("Time to wakeup?",$product,$wtr,$rdr,\$s,FALSE);
        print(" - Continuing!\n\n");
        next;
      }

      print("- CURRENT COMMAND: $cmd\n");

      #catch the sleep command
      if($cmd =~ /^sleep/)
      {
        print("WARNING - sleep command has been deprecated. Remove from your tests file\n\n");
        next;
      }
      elsif($cmd =~ /^prompt\s+(.*)$/)
      {
        prompt($1,$product,$wtr,$rdr,\$s,FALSE);
        print(" - Continuing!\n\n");
        next;
      }
      elsif($cmd eq "wait")
      {
        print(" - Catching wait command\n");
        my ($result,$cmd,$udw_ret,$out,$assert) = wait_for_clean_serial($WAIT_TIME,$wtr,$rdr,\$s,"Waiting for clean serial",\@tty_buffer,\$tty_output);

        if($result == ERROR or $udw_ret == ERROR)
        {
          print("***************************\n");
          print(" - Error in wait command.\n");
          print("   RESULT: ");
          ($result == ERROR) ? print("ERROR\n") : print("SUCCESSFUL\n");
          print(" CMD: $cmd\n");
          print("   UDW_RESULT: ");
          ($udw_ret == ERROR) ? print("ERROR\n") : print("SUCCESSFUL\n");
          print("   OUTPUT: $out\n");
          print("***************************\n\n");
        }
        print(" - Successful!\n\n");
        next;
      }
      elsif($cmd eq "reflash")
      {
        # TODO: Enable manual reflash of multiple fhx
        #print(" - Catching reflash command. First checking for available .fhx file in $base_config_dir/$product/*.fhx\n");

        while(TRUE)
        {
          check_test_time($wtr,$rdr,\$s);

          my @fhx = glob("$pkg_dir/*.fhx");

          if(@fhx)
          {
            # cleanup the old .old_fhx files
            if($REMOVE_FHX_AFTER_REFLASH > 0)
            {
              #add all old_fhx too
              my @tmp_fhx = (@fhx, glob("$pkg_dir/*.old_fhx"));

              #check the created time on each build and delete anything
              #over $REMOVE.. num of .fhx files
              my %modify_time = ();
              map{ $modify_time{(stat($_))[9]} = $_ } sort(@tmp_fhx);
              my @oldest = sort(keys(%modify_time));
              my $index = $REMOVE_FHX_AFTER_REFLASH;

              for my $old (reverse(@oldest))
              {
                if($index == 0)
                {
                  #remove the build
                  print("  - Removing old build: $modify_time{$old}\n") if($debug);
                  unlink($modify_time{$old});
                }
                else
                {
                  $index -= 1;
                }
              }
            }

            # try to load the data from the last test that was ran
            if(not %test_info)
            {
              foreach (@fhx)
              {
                print(" - Found an FHX file -> $_\n".
                      "   Deleting...\n") if($debug);
                unlink($_);
              }
              next;
  #                load_test_info($product);

              # withouth a hw_test_id our test_info is pretty worthless
              %test_info = () unless(exists $test_info{hw_test_id});

              print(" - Test_info successfully loaded to build: $test_info{build_tag}\n") if(%test_info);
              print(" - Error loading test_info\n") unless(%test_info);
            }

            # About to start reflashing each component. First, get some stats to compare against
            # if we make it to the end
            my ($result,$cmd,$udw_ret,$out,$assert) = undef;
            my ($old_rev_string,$old_build_time,$old_scm_key) = undef;
            my ($new_rev_string,$new_build_time,$new_scm_key) = undef;

            ($result,$cmd,$udw_ret,$out,$assert,$old_rev_string,$old_build_time,$old_scm_key) = get_unit_stats($wtr,$rdr,\$s,\@tty_buffer,\$tty_output);

            if($assert)
            {
              my $assert_info = "***************************\n".
                                "ASSERT!\n".
                                "CMD: $cmd\n".
                                "ASSERT INFO: \n$out\n".
                                "***************************\n";
              print("\n$assert_info\n");

              print(" - Now attempting assert recovery\n");
              my ($ret,$out) = recover_assert($usb,$serial_no);
              print(" - Back from assert recovery\n") if($debug);

              my ($submit_tty,$submit_scm_key,$submit_rev_str);
              if($package)
              {
                lock(@tty_mux_buffer);
                $submit_tty = join("", @tty_mux_buffer);
                $submit_rev_str = $old_rev_string;
              }
              else
              {
                $submit_tty = $tty_output;
                $submit_scm_key = $old_scm_key;
              }

              if($ret == ERROR)
              {
                print("  - Error during assert recovery!\nError output: $out\n") if($debug);
                submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,$assert_info,$product,$wtr,$rdr,\$s,\$submit_tty,$submit_scm_key,$submit_rev_str);

                my $prompt_msg = "Results submitted to Sirius Hub, but assert recovery failed and unit requires manual intervention.";
                $prompt_msg .= " Error output: $out" if($out);
                prompt($prompt_msg,$product,$wtr,$rdr,\$s,FALSE);

                print("\nPlease restart script when unit is ready to be tested again.\nBye!\n");
                my_exit(1,$wtr,$rdr,\$s);
              }
              else
              {
                print("  - Assert recovery successful!\n");
                submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,generate_coredump_info($out)."\n\n$assert_info",$product,$wtr,$rdr,\$s,\$submit_tty,$submit_scm_key,$submit_rev_str);

                # TODO: reflash good code, but for multiple components
              }
              last TEST_LOOP;
            }
            if($result == ERROR or $udw_ret == ERROR)
            {
              print("\n");
              print("***************************\n");
              print("Failed to get unit stats before reflashing!\n");
              print("Error output: $out\n");
              print("***************************\n");
              print("\n");

              $op = $cmd;
              $op_ret = $result;
              $op_udw_ret = $udw_ret;
              $op_out = $out;

              last;
            }

            print("WARNING: $out\n") if($out);

            my $fhx_file = $test_info{fhx_file};
            my $fhx_file_basename = File::Basename::basename($fhx_file);
            my $start_time = localtime();
            print(" - Starting reflash at -- $start_time -- for $product with file: $fhx_file_basename\n");
            ($result,$cmd,$udw_ret,$out,$assert) = reflash($fhx_file,$wtr,$rdr,\$s,$serial_no,$package,\@tty_buffer,\$tty_output);

            if($assert)
            {
              #uh oh.. an assert on reflash..
              my $assert_info = "***************************\n".
                                "ASSERT ON REFLASH!\n".
                                "CMD: $cmd\n".
                                "ASSERT INFO: \n$out\n".
                                "***************************\n";
              print("\n".$assert_info."\n");

              print(" - Now attempting assert recovery\n");
              my ($ret,$out) = recover_assert($usb,$serial_no);
              print("Back from assert recovery\n") if($debug);

              #rename the fhx so we don't just test this again!
              move_fhx_file($fhx_file);

              my ($submit_tty,$submit_scm_key,$submit_rev_str);
              if($package)
              {
                lock(@tty_mux_buffer);
                $submit_tty = join("", @tty_mux_buffer);
              }
              else
              {
                $submit_tty = $tty_output;
              }

              if($submit_tty !~ REFLASH_DONE_MARKER)
              {
                if($package)
                {
                  $submit_rev_str = $old_rev_string;
                }
                else
                {
                  $submit_scm_key = $old_scm_key;
                }
              }

              if($ret == ERROR)
              {
                print("Error from assert recovery!\n".
                      "Error output:$out\n") if($debug);

                submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,$assert_info,$product,$wtr,$rdr,\$s,\$submit_tty,$submit_scm_key,$submit_rev_str);

                my $prompt_msg = "Results submitted to Sirius Hub, but assert recovery failed and unit requires manual intervention.";
                $prompt_msg .= " Error output: $out" if($out);
                prompt($prompt_msg,$product,$wtr,$rdr,\$s,FALSE);

                print("\nPlease restart script when unit is ready to be tested again.\nBye!\n");
                my_exit(1,$wtr,$rdr,\$s);
              }
              else
              {
                print("  - Assert recovery successful!\n");
                submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,generate_coredump_info($out)."\n\n$assert_info",$product,$wtr,$rdr,\$s,\$submit_tty,$submit_scm_key,$submit_rev_str);

                #reflash_good_code($product,$serial_no,$package,"$base_config_dir/$product/$product.keep",$wtr,$rdr,\$s,\@tty_buffer);
              }

              last TEST_LOOP;
            }
            if($result == ERROR or $udw_ret == ERROR)
            {
              #Only move fhx file to old if reflash failed for reason other than the reflash getting stuck
              move_fhx_file($fhx_file) unless($out =~ /Reflash device still present/);
              print("\n");
              print("***************************\n");
              print("Reflash failed!\n");
              print("Error output: $out\n");
              print("***************************\n");
              print("\n");
              prompt("Reflash failed for $product. Error output: $out",$product,$wtr,$rdr,\$s,FALSE);

              $op = Udw_cmds::REFLASH;
              $op_ret = $result;
              $op_udw_ret = $udw_ret;
              $op_out = $out;

              last;
            }
            print("WARNING: $out\n") if($out);

            move_fhx_file($fhx_file);

            ($result,$cmd,$udw_ret,$out,$assert,$new_rev_string,$new_build_time,$new_scm_key) = get_unit_stats($wtr,$rdr,\$s,\@tty_buffer,\$tty_output);

            if($assert)
            {
              my $assert_info = "***************************\n".
                                "ASSERT!\n".
                                "CMD: $cmd\n".
                                "ASSERT INFO: \n$out\n".
                                "***************************\n";
              print("\n$assert_info\n");

              print(" - Now attempting assert recovery\n");
              my ($ret,$out) = recover_assert($usb,$serial_no);
              print(" - Back from assert recovery\n") if($debug);

              my $submit_tty;
              if($package)
              {
                lock(@tty_mux_buffer);
                $submit_tty = join("", @tty_mux_buffer);
              }
              else
              {
                $submit_tty = $tty_output;
              }

              if($ret == ERROR)
              {
                print("  - Error during assert recovery!\nError output: $out\n") if($debug);
                submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,$assert_info,$product,$wtr,$rdr,\$s,\$submit_tty);

                my $prompt_msg = "Results submitted to Sirius Hub, but assert recovery failed and unit requires manual intervention.";
                $prompt_msg .= " Error output: $out" if($out);
                prompt($prompt_msg,$product,$wtr,$rdr,\$s,FALSE);

                print("\nPlease restart script when unit is ready to be tested again.\nBye!\n");
                my_exit(1,$wtr,$rdr,\$s);
              }
              else
              {
                print("  - Assert recovery successful!\n");
                submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,generate_coredump_info($out)."\n\n$assert_info",$product,$wtr,$rdr,\$s,\$submit_tty);
                # TODO: reflash good code, but for multiple components
              }

              last TEST_LOOP;
            }

            if($result == ERROR or $udw_ret == ERROR)
            {
              print("\n");
              print("***************************\n");
              print("Failed to get unit stats after reflashing!\n");
              print("Error output: $out\n");
              print("***************************\n");
              print("\n");

              $op = $cmd;
              $op_ret = $result;
              $op_udw_ret = $udw_ret;
              $op_out = $out;

              last;
            }

            print("WARNING: $out\n") if($out);

            my $end_time = localtime();
            print("***************************\n");
            print("$product HAS BEEN REFLASHED -- $end_time --\n");
            print("WARNING: The reported revision string and build times did not change!\n") if($old_rev_string eq $new_rev_string and $old_build_time eq $new_build_time);
            print("***************************\n");
            print("\n");

            ($ret,$cmd,$udw_ret,$out,$assert) = get_serial_number($wtr,$rdr,\$s,\@tty_buffer,\$tty_output);
            if($ret == ERROR or $udw_ret == ERROR)
            {
              prompt("Error reading serial number after reflash. Please check all connections to printer.",$product,$wtr,$rdr,\$s);
              print("\nPlease restart the script when the issue has been resolved.\nBye!\n");
              my_exit(1,$wtr,$rdr,\$s);
            }

            if($serial_no ne $out)
            {
              print("WARNING: The serial number appears to have changed after reflash!! ($serial_no -> $out)\n");
              $serial_no = $out;
            }

            ### FIND ALL USB DEVICES ###
            my $tmp_usb = search_usb_devices($mappings{$product},$serial_no);
            unless($tmp_usb)
            {
              print("ERROR: Could not find $product (mapped to $mappings{$product} <-> $serial_no) on USB after reflash!!\n");

              my $submit_tty;
              if ($package)
              {
                lock(@tty_mux_buffer);
                $submit_tty = join("", @tty_mux_buffer);
              }
              else
              {
                $submit_tty = $tty_output;
              }

              submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,"Unit failed to enumerate on USB after reflash",$product,$wtr,$rdr,\$s,\$submit_tty);

              print("\nPlease restart script when unit is ready to be tested again.\nBye!\n");
              my_exit(1,$wtr,$rdr,\$s);
            }

            if($tmp_usb ne $usb)
            {
              print("***************************\n");
              print("The device has switched USB ports. Used to be on $usb now on $tmp_usb\n");
              print("***************************\n");
              print("\n");
              $usb = $tmp_usb;
            }

            $op = Udw_cmds::REFLASH;
            $op_ret = $result;
            $op_udw_ret = $udw_ret;
            $op_out = $out;

            ($result,$cmd,$udw_ret,$out,$assert) = post_reflash_tasks($wtr,$rdr,\$s,\@tty_buffer,\$tty_output,$package);

            if($assert)
            {
              my $assert_info = "***************************\n".
                                "ASSERT!\n".
                                "CMD: $cmd\n".
                                "ASSERT INFO: \n$out\n".
                                "***************************\n";
              print("\n$assert_info\n");

              print(" - Now attempting assert recovery\n");
              my ($ret,$out) = recover_assert($usb,$serial_no);
              print(" - Back from assert recovery\n") if($debug);

              my $submit_tty;
              if($package)
              {
                lock(@tty_mux_buffer);
                $submit_tty = join("", @tty_mux_buffer);
              }
              else
              {
                $submit_tty = $tty_output;
              }

              if($ret == ERROR)
              {
                print("  - Error during assert recovery!\nError output: $out\n") if($debug);
                submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,$assert_info,$product,$wtr,$rdr,\$s,\$submit_tty);

                my $prompt_msg = "Results submitted to Sirius Hub, but assert recovery failed and unit requires manual intervention.";
                $prompt_msg .= " Error output: $out" if($out);
                prompt($prompt_msg,$product,$wtr,$rdr,\$s,FALSE);

                print("\nPlease restart script when unit is ready to be tested again.\nBye!\n");
                my_exit(1,$wtr,$rdr,\$s);
              }
              else
              {
                print("  - Assert recovery successful!\n");
                submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,generate_coredump_info($out)."\n\n$assert_info",$product,$wtr,$rdr,\$s,\$submit_tty);

                # TODO: reflash good code, but for multiple components
              }

              last TEST_LOOP;
            }

            if($result == ERROR or $udw_ret == ERROR)
            {
              print("\n");
              print("***************************\n");
              print("Failed to get unit stats after reflashing!\n");
              print("Error output: $out\n");
              print("***************************\n");
              print("\n");
              $op = $cmd;
              $op_ret = $result;
              $op_udw_ret = $udw_ret;
              $op_out = $out;

              last;
            }

            print("WARNING: $out\n") if($out);

            last;
          }
          else
          {
            #try to download a new FHX file for testing
            print(" - No .fhx file found in directory.\n".
                  "   Connecting to Sirius Hub to find latest untested build\n");
            print("  - For product = $product\n");

            unless($ATTEMPT_FHX_DOWNLOAD)
            {
              print(" - WARNING: You have set NOT to attempt to download .fhx files from SiriusDB. Attempting search for local .fhx files again\n");
              sleep(30);
              next;
            }

            my $download_attempts = 3;
            my ($ret,$out);

            while($download_attempts)
            {
              print("  - Beginning database query\n");
              ($ret,$out) = download_fhx($product,$package);

              last if($ret == SUCC);

              if($out =~ /no ci config found/i)
              {
                print("   - $out\n".
                      "     Restart this script after a CI Config has been created\n");
                my_exit(1,$wtr,$rdr,\$s);
              }
              elsif($out =~ /not configured for ci testing/i)
              {
                print("   - $out\n".
                      "     CI Config must be active, Priority 1, and on 'trunk' branch.\n");
                my_exit(1,$wtr,$rdr,\$s);
              }
              elsif($out =~ /not a tester/i)
              {
                print("   - $out\n".
                      "     Tester must sign up as a Sirius Hub user and request tester role.\n");
                my_exit(1,$wtr,$rdr,\$s);
              }

              print("   - Problem trying to download fhx.\n".
                    "     Error output: $out\n".
                    "     Will attempt $download_attempts more times\n");
              $download_attempts -= 1;
            }

            if($ret == ERROR)
            {
              if($out =~ /not found/i)
              {
                print("   - Could not find the FHX file to download. It has probably been removed.\n".
                      "     Sleeping for 5 minutes then will check if a more recent build has been created\n");
                sleep(300);
                next;
              }
              else
              {
                #if the prompt call returns then they hit continue
                prompt("Error trying to download the FHX file. Error output: $out. Would you like to continue with the testing even though a new FHX has not been downloaded?",$product,$wtr,$rdr,\$s,FALSE);
                last;
              }
            }
            #means everything worked ok, but no file to download yet
            elsif($out and $out =~ /no (?:build|package) found/i)
            {
              print("   - Nothing to download. Sleeping for 5 minutes then trying again\n");
              sleep(300);
              next;
            }
            elsif($out)
            {
              print("   - $out\n");
              next;
            }
            else
            {
              #file has been downloaded to $out!!
              print("   - Successful download of FHX files!\n");
              next;
            }
          }
        }
        $cmd = "";
      }
      elsif($cmd eq "exit")
      {
        print(" - Caught exit command\n");
        my_exit(0,$wtr,$rdr,\$s);
      }
      #the print path should be relative to the $base_picture_dir
      elsif($cmd =~ /^print\s+(\S+)/)
      {
        my $picture = $1;

        unless(-e "$base_picture_dir/$picture")
        {
          print(" - Could not print picture $picture because the picture could not be found at $base_picture_dir/$picture\n\n");
          next;
        }

        ### SEND THE PICTURE OVER USB ###
        $op_ret = cat("$base_picture_dir/$picture",$USB_WAIT_TIMEOUT,$usb,$mappings{$product},$serial_no);

        print(" - Back from cat function\n") if($debug);

        #make sure we printed without asserts
        $op = "Attempting to print this image: $base_picture_dir/$picture";
        $cmd = "";
      }
      elsif($cmd eq "report")
      {
        #make sure we have enough information to edit
        unless(exists($test_info{hw_test_id}))
        {
          prompt("Report command caught, but don't have necessary information.",$product,$wtr,$rdr,\$s,FALSE);
          print(" - Continuing!\n\n");
          next;
        }

        my $tty_submit;
        if($package)
        {
          lock(@tty_mux_buffer);
          $tty_submit = join("", @tty_mux_buffer);
        }
        else
        {
          $tty_submit = $tty_output;
        }
        submit_results($test_info{hw_test_id},SiriusHub::TEST_PASS,"",$product,$wtr,$rdr,\$s,\$tty_submit);
        print(" - Successful!\n\n");
        next;
      }


      ############################################
      # Expand commands
      #
      #Check if cmd is something we need to expand
      if($cmd)
      {
        my @words = split(/\s+/,$cmd);
        my $first = shift(@words);
        if(exists($commands{$first}))
        {
          print(" - Expanding $first -> $commands{$first}\n");
          $cmd = $commands{$first};
          map{$cmd .= " $_ "} @words;
          print(" - Final command is: $cmd\n") if($debug);
        }
      }
      ############################################

      #check if we have the proper image to print from if photo printing
      if ($cmd =~ /jm_ph_prt\.\w+\s+(\d)/)
      {
        unless($num_images)
        {
          print " - SKIPPING photo print job because no images were available when test started\n";
          next;
        }
        elsif ($1 > $num_images)
        {
          print " - SKIPPING photo print job. Attempted to print image $1 and only $num_images exist\n";
          next;
        }
      }

      my $cmd_ret = SUCC;
      my ($ret,$udw_ret,$out,$assert);

      if($op)
      {
        $cmd = $op;
        $ret = $op_ret;
        $udw_ret = $op_udw_ret;
        $out = $op_out;
      }
      else
      {
        ($ret,$cmd,$udw_ret,$out,$assert) = send_cmd($cmd,$wtr,$rdr,\$s,\@tty_buffer,\$tty_output);

        chomp($out);
        chomp($cmd);
      }

      if($assert)
      {
        my $assert_info = "***************************\n".
              "ASSERT!\n".
              "CMD: $cmd\n".
              "ASSERT INFO: \n$out\n".
              "***************************\n";
        print("\n".$assert_info."\n");

        print("Attempting assert recovery\n") if($debug);
        ($ret,$out) = recover_assert($usb,$serial_no);
        print("Back from assert recovery\n") if($debug);

        my $submit_tty;
        if($package)
        {
          lock(@tty_mux_buffer);
          $submit_tty = join("", @tty_mux_buffer);
        }
        else
        {
          $submit_tty = $tty_output;
        }

        if($ret == ERROR)
        {
          print("Error from assert recovery!\n".
                "Error output:$out\n\n") if($debug);
          submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,$assert_info,$product,$wtr,$rdr,\$s,\$submit_tty);

          my $prompt_msg = "Results submitted to Sirius Hub, but assert recovery failed and unit requires manual intervention.";
          $prompt_msg .= " Error output: $out" if($out);
          prompt($prompt_msg,$product,$wtr,$rdr,\$s,FALSE);

          print("\nPlease restart the script when the unit is ready to be tested again.\nBye!\n");
          my_exit(1,$wtr,$rdr,\$s);
        }
        else
        {
          print("Assert recovery successful!\n") if($debug);
          submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,generate_coredump_info($out)."\n\n$assert_info",$product,$wtr,$rdr,\$s,\$submit_tty);
          #reflash_good_code($product,$serial_no,$package,"$base_config_dir/$product/$product.keep",$wtr,$rdr,\$s,\@tty_buffer);
        }
        last;
      }
      elsif($ret == ERROR or (defined($udw_ret) and $udw_ret == ERROR))
      {
        if($ret == ERROR)
        {
          $ret = "ERROR";
        }
        elsif($ret == SUCC)
        {
          $ret = "SUCCESS";
        }

        if(defined($udw_ret) and $udw_ret == ERROR)
        {
          $udw_ret = "ERROR";
        }
        elsif(defined($udw_ret) and $udw_ret == SUCC)
        {
          $udw_ret = "SUCCESS";
        }

        print("\n");
        print("***************************\n");
        print("ERROR!\n");
        print("RESULT: $ret\n");
        print("CMD EXECUTED: $cmd\n");
        print("RESULT OF COMMAND: $udw_ret\n") if($udw_ret);
        print("CMD OUTPUT: $out\n") if($out);
        print("***************************\n\n");

        #if the cmd itself returned an error (NOT the return value of command)
        #then exit too..

        if($ret eq "ERROR" and defined($op) and $op_ret == ERROR)
        {
          print("The command has returned an error code.\n".
              "This test will now be abandoned and may be left marked as 'Incomplete'.\n\n");
          last;
        }

        my_exit(1,$wtr,$rdr,\$s) if($ret eq "ERROR" or $QUIT_AFTER_ERROR);

        $cmd_ret = ERROR;
      }

      ($ret,$assert,$out) = wait_for_idle($wtr,$rdr,\$s,$cmd,$WAIT_TIME,$product,\@tty_buffer,\$tty_output);

      if($assert)
      {
        my $assert_info = "***************************\n".
                          "ASSERT!\n".
                          "CMD: $cmd\n".
                          "ASSERT INFO: \n$out\n".
                          "***************************\n";
        print("\n".$assert_info."\n");

        print("Attempting assert recovery\n") if($debug);
        ($ret,$out) = recover_assert($usb,$serial_no);
        print("Back from assert recovery\n") if($debug);

        my $submit_tty;
        if($package)
        {
          lock(@tty_mux_buffer);
          $submit_tty = join("", @tty_mux_buffer);
        }
        else
        {
          $submit_tty = $tty_output;
        }

        if($ret == ERROR)
        {
          print("Error from assert recovery!\n".
              "Error output: $out\n\n") if($debug);
          submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,$assert_info,$product,$wtr,$rdr,\$s,\$submit_tty);

          my $prompt_msg = "Results submitted to Sirius Hub, but assert recovery failed and unit requires manual intervention.";
          $prompt_msg .= " Error output: $out" if($out);

          prompt($prompt_msg,$product,$wtr,$rdr,\$s,FALSE);
          print("\nPlease restart the script when the unit is ready to be tested again.\nBye!\n");
          my_exit(1,$wtr,$rdr,\$s);
        }
        else
        {
          print("Assert recovery successful!\n") if($debug);
          submit_results($test_info{hw_test_id},SiriusHub::TEST_FAIL,generate_coredump_info($out)."\n\n$assert_info",$product,$wtr,$rdr,\$s,\$submit_tty);
          #reflash_good_code($product,$serial_no,$package,"$base_config_dir/$product/$product.keep",$wtr,$rdr,\$s,\@tty_buffer);
        }
        last;
      }
      elsif($ret == ERROR)
      {
        # deal with error
      }
      else
      {
        print(" - Successful!\n\n") if($cmd_ret == SUCC);
        print(" - Failed!\n\n") if($cmd_ret == ERROR);
      }

      # stub - verify things happened and we return to idle for next command
      if($cmd_ret == SUCC)
      {
        push(@{$test_info{passed}}, $cmd) if($test_info{passed});
        push(@{$test_info{passed}}, (time() - $cmd_start) ) if($test_info{passed});

      }
      else
      {
        push(@{$test_info{failed}}, $cmd) if($test_info{failed});
        push(@{$test_info{failed}}, (time() - $cmd_start) ) if($test_info{failed});
      }
    }

    print("***************************\n");
    print(" Testing cycle done. Sleeping for 30 seconds\n");
    print("***************************\n\n\n");
    sleep(30);
  }
}

sub my_exit($$$$)
{
  my ($ret,$wtr,$rdr,$s) = @_;

  foreach(@reader_threads)
  {
    $_ -> kill('STOP');
    $_ -> join();
  }
  close_connection($wtr,$rdr,$s) if($wtr and $rdr and $s);
  foreach(@children) { kill('TERM', $_); }
  exit($ret);
}

sub create_single_fhx($$)
{
  my @fhx_files = @{shift @_};
  my $output_file = shift @_;

  return(ERROR,"No FHX files supplied") unless(@fhx_files);

  # If only a single FHX file, simply write it out and return
  if(scalar(@fhx_files) == 1)
  {
    print("   - Writing out single FHX file\n") if($debug);
    open(FHX_FILE, '>', $output_file) or return(ERROR,"Could not open file $output_file for writing: $!");
    print FHX_FILE $fhx_files[0];
    close(FHX_FILE);
    return(SUCC,undef);
  }

  # Extract the boot loader from the first FHX
  print("   - Extracting boot code\n") if($debug);
  my $boot_code;
  open(FHX_FILE, '<', \$fhx_files[0]) or return(ERROR,"Could not open internal file handle: $!");
  foreach my $line (<FHX_FILE>)
  {
    next if($line =~ /^SA/);
    last if($line =~ /^F/);
    $boot_code .= $line;
  }
  close(FHX_FILE);
  printf("    - Extracted boot code is %d bytes\n", length($boot_code)) if($debug);

  # Extract the payload from each of the FHX files
  my @payloads = ();
  foreach my $fhx_file (@fhx_files)
  {
    my $payload;
    printf("   - Extracting payload from %d-byte FHX file\n", length($fhx_file)) if($debug);
    open(FHX_FILE, '<', \$fhx_file) or return(ERROR,"Could not open internal file handle: $!");
    foreach my $line (<FHX_FILE>)
    {
      # Once the payload has been detected, continue appending until the end
      if($payload)
      {
        $payload .= $line;
      }
      elsif($line =~ /^P/)
      {
        $payload = $line;
      }
    }
    close(FHX_FILE);
    printf("    - Extracted payload is %d bytes\n", length($payload)) if($debug);
    push(@payloads,$payload);
  }

  # Construct the final FHX file, laid out as follows:
  #   1) Boot Loader Application
  #   2) 32-bit payload size (sum of all payloads)
  #   3) Each individual partition's payload
  my $payload_sum = 0;
  foreach(@payloads) { $payload_sum += length($_); }
  print("   - Combined payload is $payload_sum bytes\n") if($debug);
  open(FHX_FILE, '>', $output_file) or return(ERROR,"Could not open file $output_file for writing: $!");
  print("   - Writing boot code\n") if($debug);
  print FHX_FILE $boot_code;
  print("   - Writing payload header\n") if($debug);
  printf FHX_FILE "F%08X\n", $payload_sum;
  print("   - Writing payload\n") if($debug);
  foreach(@payloads) { print FHX_FILE $_; }
  close(FHX_FILE);
  print("   - Final FHX file written to $output_file\n") if($debug);
  return(SUCC,undef);
}

sub construct_fhx_location($)
{
  my $path = shift @_;

  print("   - Searching for FHX at following location: $path\n") if($debug);
  # if there isn't a '/' at the end, add one
  if (not $path =~ /\/$/)
  {
    $path = $path."/";
  }

  # to get the fhx file, we download the index.html file in the product_target folder
  # of this build and look in the html code for the fhx file's name. extracting the name
  # this way ensures that a change in naming conventions won't break the script
  my $ua = LWP::UserAgent->new(max_redirect => 5, timeout => 30);
  my $response = $ua->get($path);

  if ($response->is_success and $response->content =~ /href=['"]([^'"]*\.fhx)['"]/i)
  {
    return($path.$1);
  }
  else
  {
    return(undef);
  }
}

sub download_file($$$)
{
  my ($ua,$url,$out) = @_;

  my $response = $ua->head($url);
  return(ERROR,"Unable to access file at $url") unless($response->is_success);

  my $data;
  if($response->content_length)
  {
    # We know the length of the file to download, give some progress feedback
    my $total_size = $response->content_length;
    my $total_progress = 0;
    my $progress = 0;
    my $progress_printed;
    my $callback = sub
    {
      $data .= shift @_;
      $progress = (length($data) / $total_size) * 100;
      if (($progress - $total_progress) >= 2)
      {
        $total_progress += 2;
        print ".";
        $progress_printed = 1;
      }
    };
    print("    - ");
    $response = $ua->get($url, ':content_cb' => \&{$callback});
    print("\n") if($progress_printed);
    return(ERROR,"Download size of file does not match HEAD size") if($response->is_success and length($data) != $total_size);
  }
  else
  {
    # Length of file unknown, shoot in the dark...
    $response = $ua->get($url);
    $data = $response->content;
  }

  unless($response->is_success and $data)
  {
    print("***************************\n");
    print("- Problem downloading file!\n");
    print("***************************\n");
    return(ERROR,"Downloaded failed for file $url");
  }

  ${$out} = $data;
  return(SUCC,undef);
}

#returns ($ret,$out)
#if $ret == ERROR then check $out for error str
#if $ret == SUCC then check $out for path to file
#  unless($out) then couldn't find any newer untested builds to download!
sub download_fhx($$)
{
  my $product = shift @_;
  my $package = shift @_;

  #clear out the test_info hash in case we had older tests that we ran
  %test_info = ();

  my ($ret,$out) = autotest_queue($product,$package);

  #check that neither query had errors first.. exit/retry if so
  return(ERROR, $out) if($out);

  my %queue_hash = %{$ret};

  #check that all hash elements are there as expected.
  return(ERROR,"Could not find status key in response hash") unless(exists $queue_hash{status});
  if($queue_hash{status} eq SiriusHub::JSON_ERROR)
  {
    return(ERROR,$queue_hash{message});
  }
  elsif(exists $queue_hash{data}{message})
  {
    return(SUCC,$queue_hash{data}{message});
  }

  my %queue_data_hash = %{$queue_hash{data}};
  return(ERROR,"Could not find build_result_id in response hash") if(not $package and not exists($queue_data_hash{build_result_id}));
  return(ERROR,"Could not find package_result_id in response hash") if($package and not exists($queue_data_hash{package_result_id}));

  my $db_build_or_package_result_id = undef;
  my $db_build_or_package_time = undef;
  my $db_cset = undef;
  my @fhx_urls = ();

  if(exists($queue_data_hash{build_result_id}))
  {
    return(ERROR,"Could not find build_time key in response hash") unless(exists($queue_data_hash{build_time}));
    return(ERROR,"Could not find cset key in response hash") unless(exists($queue_data_hash{cset}));
    return(ERROR,"Could not find targets key in response hash") unless(exists($queue_data_hash{targets}));
    return(ERROR,"Targets key does not map to array in response hash") unless(ref($queue_data_hash{targets}) eq "ARRAY");

    $db_build_or_package_result_id = $queue_data_hash{build_result_id};
    $db_build_or_package_time = $queue_data_hash{build_time};
    $db_cset = $queue_data_hash{cset};

    print("   - New build found!\n");
    print("  - Beginning FHX download\n");

    my %test_targets = ();
    for my $target (@{$queue_data_hash{targets}})
    {
      my %target_hash = %{$target};

      #check that all hash elements are there as expected.
      return(ERROR,"Could not find build_product key in inner targets hash") unless(exists($target_hash{build_product}));
      return(ERROR,"Could not find target key in inner targets hash") unless(exists($target_hash{target}));
      return(ERROR,"Could not find location_of_binaries key in inner targets hash") unless(exists($target_hash{location_of_binaries}));
      return(ERROR,"Could not find load_order key in inner targets hash") unless(exists($target_hash{load_order}));

      my %info_hash = ();
      $info_hash{product} = $target_hash{build_product};
      $info_hash{target} = $target_hash{target};
      $info_hash{location_of_binaries} = $target_hash{location_of_binaries};

      my $fhx_location = construct_fhx_location($target_hash{location_of_binaries});
      return(ERROR,"Could not locate FHX file in build directory for $info_hash{product} $info_hash{target}") unless($fhx_location);

      print("    - FHX location for $info_hash{product} $info_hash{target}: $fhx_location\n") if($debug);
      $info_hash{fhx_location} = $fhx_location;
      $test_targets{$target_hash{load_order}} = \%info_hash;
    }

    # Sort URLs by load order
    for my $key (sort keys %test_targets)
    {
      my %info_hash = %{$test_targets{$key}};
      push(@fhx_urls,$info_hash{fhx_location});
    }
  }
  elsif(exists($queue_data_hash{package_result_id}))
  {
    return(ERROR,"Could not find package_time key in response hash") unless(exists($queue_data_hash{package_time}));
    return(ERROR,"Could not find location_of_binaries in response hash") unless(exists($queue_data_hash{location_of_binaries}));

    $db_build_or_package_result_id = $queue_data_hash{package_result_id};
    $db_build_or_package_time = $queue_data_hash{package_time};

    print("   - New package found!\n");
    print("  - Beginning FHX download\n");

    my $fhx_location = construct_fhx_location($queue_data_hash{location_of_binaries});
    return(ERROR,"Could not locate FHX file in package directory for $product") unless($fhx_location);

    print("     - FHX location for $product: $fhx_location\n") if($debug);
    push(@fhx_urls,$fhx_location);
  }

  # Now download each FHX file
  my @fhx_files = ();
  my $ua = LWP::UserAgent->new(max_redirect => 5, timeout => 30);
  foreach my $url (@fhx_urls)
  {
    my $fhx_file;
    my $filename = File::Basename::basename($url);

    print("   - Downloading $filename\n") if($debug);

    ($ret,$out) = download_file($ua,$url,\$fhx_file);
    return(ERROR,$out) if($ret);

    printf("    - Successful download of FHX file (%d bytes)\n", length($fhx_file)) if($debug);
    push(@fhx_files,$fhx_file);
  }

  # Create a single FHX file for reflash
  my $timestamp;
  if($db_build_or_package_time =~ /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):\d{2}/)
  {
    $timestamp = "$1$2$3_$4$5";
  }
  else
  {
    $timestamp = strftime("%Y%m%d_%H%M", localtime);
  }
  my $fhx_output_file = "$base_config_dir/$product/$product"."_".$timestamp.".fhx";
  ($ret,$out) = create_single_fhx(\@fhx_files,$fhx_output_file);
  return(ERROR,$out) if($ret);

  #we need to request the test here..
  ($ret, $out) = autotest_request_test($SIRIUS_HUB_USER_EMAIL,$db_build_or_package_result_id,$package);
  return(ERROR,"Could not request the test. Error output: $out") if($out);

  my %request_hash = %{$ret};
  return(ERROR,$request_hash{message}) if($request_hash{status} eq SiriusHub::JSON_ERROR);

  print(" - Successfully requested test from Sirius Hub\n") if($debug);

  my %request_data_hash = %{$request_hash{data}};
  return(ERROR,"Could not find hw_test_id key in request hash") unless(exists $request_data_hash{hw_test_id});

  my $db_hw_test_id = $request_data_hash{hw_test_id};

  print(" ** YOU HAVE REQUESTED THIS TEST: **\n");
  print("  - Test Info Product    -> $product\n");
  print("  - Test Info Cset       -> $db_cset\n") if($db_cset);
  print("  - Test Info Build Time -> $db_build_or_package_time\n");
  print("  - Test Info HW Test ID -> $db_hw_test_id\n");

  $test_info{product} = $product;
  $test_info{build_result_id} = $db_build_or_package_result_id unless($package);
  $test_info{package_result_id} = $db_build_or_package_result_id if($package);
  $test_info{hw_test_id} = $db_hw_test_id;
  $test_info{build_tag} = $db_build_or_package_time;
  $test_info{fhx_file} = $fhx_output_file;
  $test_info{failed} = [];
  $test_info{passed} = [];

  ### Remove all the old .html files in directory
  unlink("$base_config_dir/$product/*.html");

#  record_test_info($bio_product);

  return(SUCC,undef);
}

sub prompt($;$$$$$)
{
  my $message = shift @_;
  my ($product,$wtr,$rdr,$s,$return) = @_;

  my $title = ($product) ? "Automatic Testing Notification for $product" : "Automatic Testing Notification";

  $message =~ s/\n$//;

  #remove all single quotes from output
  $message =~ s/'//g;

  #print a system beep
  print("\a");
  print("***************************\n");
  print("***************************\n");
  print("Please see pop-up message for prompt\n");
  print("***************************\n");
  print("***************************\n");
  my ($ret,$out) = command("$prompt \"$title\" \"$message\"");

  #return with an answer if $return is true
  # bk prompt exits with 0 if you click Yes
  # but 0 == FALSE
  # switch this function so not confusing on
  # receiving side
  return(FALSE) if($return and $ret);
  return(TRUE) if($return);

  if($ret)
  {
    print("Bye!\n");
    my_exit(1,$wtr,$rdr,$s);
  }
  return;
}

sub load_settings()
{
  return unless(-r "$base_config_dir/settings");

  open(SETTINGS, "$base_config_dir/settings") or die ("Cannot open settings file: $!\n");
  my @lines = <SETTINGS>;
  close(SETTINGS);

  #take out comments
  @lines = grep(!/^\s*#/,@lines);

  print("- Load settings\n") if($debug);

  for my $line (@lines)
  {

    if($line =~ /^\s*TEST_FILE_ATTEMPTS\s+(\d+)/)
    {
      print(" Setting TEST_FILE_ATTEMPTS to $1\n") if($debug);
      $TEST_FILE_ATTEMPTS = $1;
    }
    elsif($line =~ /^\s*QUIT_AFTER_ERROR\s+(\d+)/)
    {
      print(" Setting QUIT_AFTER_ERROR to $1\n") if($debug);
      $QUIT_AFTER_ERROR = $1;
    }
    elsif($line =~ /^\s*ATTEMPT_FHX_DOWNLOAD\s+(\d+)/)
    {
      print(" Setting ATTEMPT_FHX_DOWNLOAD to $1\n") if($debug);
      $ATTEMPT_FHX_DOWNLOAD = $1;
    }
    elsif($line =~ /^\s*REMOVE_FHX_AFTER_REFLASH\s+(\d+)/)
    {
      print(" Setting REMOVE_FHX_AFTER_REFLASH to $1\n") if($debug);
      $REMOVE_FHX_AFTER_REFLASH = $1;
    }
    elsif($line =~ /^\s*USB_WAIT_TIMEOUT\s+(\d+)/)
    {
      print(" Setting USB_WAIT_TIMEOUT to $1\n") if($debug);
      $USB_WAIT_TIMEOUT = $1;
    }
    elsif($line =~ /^\s*MAPPING\s+(\S+)\s+(\S+)/)
    {
      print(" Mapping $2 to model number $1\n") if($debug);
      $mappings{$2} = ($1);
    }
    elsif($line =~ /^\s*COMMAND\s+(\S+)\s+(.*)\s*/)
    {
      print(" Command $1 to udw: $2\n") if($debug);
      $commands{$1} = $2;
    }
    elsif($line =~ /^\s*WAIT_TIME\s+(\d+)/)
    {
      print(" Setting WAIT_TIME to $1\n") if($debug);
      $WAIT_TIME = $1;
    }
    elsif($line =~ /^\s*SERVER_PATH\s+(.*)\s*/)
    {
      print(" Server path to: $1\n") if($debug);
      $SERVER_PATH = $1;
      $SERVER_PATH =~ s/\/$//;
    }
    elsif($line =~ /^\s*SERVER\s+(.*)\s*/)
    {
      print(" Server to: $1\n") if($debug);
      $SERVER = $1;
      $SERVER =~ s/\/$//;
    }
    elsif($line =~ /^\s*ALWAYS_SAFE_REFLASH\s+(.*)\s*/)
    {
      print(" Always safe reflash to: $1\n") if($debug);
      $ALWAYS_SAFE_REFLASH = $1;
      $ALWAYS_SAFE_REFLASH =~ s/\/$//;
    }
    elsif($line =~ /^\s*SIRIUS_HUB_USER_EMAIL\s+(.*)\s*/)
    {
      print(" Sirius Hub user email: $1\n") if($debug);
      $SIRIUS_HUB_USER_EMAIL = $1;
      $SIRIUS_HUB_USER_EMAIL =~ s/\/$//;
    }
    elsif($line =~ /^\s*JOB_FILTERS\s+(.*)\s*/)
    {
      print(" Job filters: $1\n") if($debug);
      @JOB_FILTERS = split(/\s+/, $1);
    }
    elsif($line =~ /^\s*TTY\s+(\S+)\s+(\S+)\s+(\S+)/)
    {
      print(" TTY mapping: $1 $2 $3\n") if($debug);
      $tty_mappings{$1}{$2} = $3;
    }
  }

  # if $SERVER and $SERVER_PATH aren't defined, then lets try to figure them out
  # SERVER is the http://$HOSTNAME:8000/
  unless($SERVER)
  {
    my $hostname = (uname())[1];
    my $address = gethostbyname($hostname);
    if(defined($address))
    {
      #get full name
      my $h2 = gethostbyaddr($address, AF_INET);
      $SERVER = "http://$h2:8000" if(defined($h2));
    }
  }
  unless($SERVER_PATH)
  {
    $SERVER_PATH = getcwd()."/".$coredump_dir_name;

    # full path would be
    mkdir($SERVER_PATH) unless (-e $SERVER_PATH)
  }

  return;
}

sub construct_server_path($)
{
  my $coredump_file = shift @_;

  return("coredump file not defined") unless($coredump_file);
  return("coredump file not found") unless(-e $coredump_file);

  #we found the file, now move it to the right place
  if(exists $test_info{product})
  {
    if(-e "$SERVER_PATH/$test_info{product}" or mkdir("$SERVER_PATH/$test_info{product}"))
    {
      if(-e "$SERVER_PATH/$test_info{product}/$test_info{build_tag}" or mkdir("$SERVER_PATH/$test_info{product}/$test_info{build_tag}"))
      {
        #move the coredump file to the correct location
        my ($ret,$out) = command("$mv $coredump_file $SERVER_PATH/$test_info{product}/$test_info{build_tag}/");

        if($ret)
        {
          print(" - Problem moving coredump file to new location. Error output: $out\n");
          return($coredump_file);
        }

        #figure out the server location
        $coredump_file = "$SERVER_PATH/$test_info{product}/$test_info{build_tag}/".File::Basename::basename($coredump_file);
        my $final_location = $SERVER.$coredump_file;
        $final_location =~ s/$SERVER_PATH//;

        print(" - Final calculated coredump location: $final_location\n");
        return($final_location);
      }
      else
      {
        print(" - Could not create directory at $SERVER_PATH/$test_info{product}/$test_info{build_tag} for coredump file\n") if($debug);
        return($coredump_file);
      }
    }
    else
    {
      print(" - Could not create directory at $SERVER_PATH/$test_info{product} for coredump file\n") if($debug);
      return($coredump_file);
    }
  }
  else
  {
    print(" - Test_info{product} not defined, so cannot continue with coredump processing\n") if($debug);
    return($coredump_file);
  }
}

sub generate_coredump_info($)
{
  my @coredump_files = @{shift @_};
  my @coredump_urls;

  #SERVER or SERVER_PATH not defined in settings file. Cannot continue
  return("") unless($SERVER and $SERVER_PATH);

  for my $file (@coredump_files)
  {
    push(@coredump_urls,construct_server_path($file));
  }

  if(@coredump_urls)
  {
    if (scalar(@coredump_urls) == 1)
    {
      return("COREDUMP LOCATION: $coredump_urls[0]");
    }
    else
    {
      return("COREDUMP_LOCATIONS:\n".join("\n",@coredump_urls));
    }
  }
  else
  {
    return("");
  }
}

sub reflash_good_code($$$$$$$$$)
{
  my ($prod,$serial_no,$package,$file,$wtr,$rdr,$s,$tty_buffer) = @_;

  unless($ALWAYS_SAFE_REFLASH)
  {
    my $answer = prompt("Would you like reflash to a safe build before continuing?",$prod,$wtr,$rdr,$s,TRUE);

    if($answer == FALSE)
    {
      print(" - Safe reflash skipped\n") if($debug);
      return;
    }
  }

  print(" - Attempting safe reflash\n");
  my %tmp = reverse(%mappings);
  my ($result,$cmd,$udw_ret,$out,$assert) = safe_reflash($tmp{$prod},$serial_no,$package,$file,$wtr,$rdr,$s,$tty_buffer);

  if($assert)
  {
    #uh oh.. assert while trying to do the safe reflash probably means
    # something on boot.. in trouble
    print("  - Error from assert recovery!\n".
          "    Error output: $out\n\n") if($debug);
    prompt("$prod asserted agagin while trying to reflash with $prod.keep file. Manual intervention required.",$prod,$wtr,$rdr,$s);
  }
  elsif($result == ERROR or $udw_ret == ERROR)
  {
    # had a problem with the safe_reflash.. continue on?
    print("  - Error from assert recovery!\n".
        "    Error output: $out\n");
    print("  - Going to continue on and hope things get better...\n\n");
  }
  else
  {
    if($out)
    {
      print("  - Safe reflash output: $out\n\n");
    }
    else
    {
      print("  - Safe reflash a success!\n\n");
    }
  }
}

sub move_fhx_file($)
{
  my $path = shift @_;
  my $file = File::Basename::basename($path);

  if($file =~ m/\.fhx$/)
  {
    my $dir = File::Basename::dirname($path);
    $file =~ s/\.fhx$/\.old_fhx/;
    my $new_path = "$dir/$file";
    print("Moving FHX to new location: $new_path\n");
    my ($ret,$out) = command("$mv $path $new_path");
    print("WARNING: Problem moving the FHX file from $path to $new_path. Error output: $out\n") if($ret);
  }
}

### RECORD ALL TEST_INFO IN FILE SO CAN BE RECOVERED AGAIN ###
sub record_test_info($)
{
  my $prod = shift @_;

  return unless(%test_info);
  open(TEST, ">$base_config_dir/$prod/$test_info_file_name") or die("Cannot open $base_config_dir/$prod/$test_info_file_name for writing: $!\n");
  print TEST encode_json(\%test_info);
  close(TEST);

  return();
}

sub load_test_info($)
{
  my $prod = shift @_;

  print(" - Attempting to load test_info from file: $base_config_dir/$prod/$test_info_file_name\n") if($debug);
  open(TEST,"$base_config_dir/$prod/$test_info_file_name") or die("Cannot open file at $base_config_dir/$prod/$test_info_file_name: $!\n");
  %test_info = %{decode_json(<TEST>)};
  close(TEST);

  return();
}

sub submit_results($$$$$$$;$$$)
{
  my ($hw_test_id,$result,$problems,$prod,$wtr,$rdr,$s,$tty_output,$scm_key,$rev_str) = @_;

  unless($hw_test_id)
  {
    prompt("Trying to submit results, but don't have necessary information.",$prod,$wtr,$rdr,$s,FALSE);
    return;
  }

  my $comments = "";

  #create the $comments to pass
  $comments .= " - LISTED BELOW ARE THE UDW COMMANDS THAT WERE RUN AS PART OF AUTOMATED CR TESTING:\n";
  $comments .= "  * THE COMMAND 'reflash' IS DONE BY EXECUTING 'udws udw.srec_download' THEN \n";
  $comments .= "    'cat'ing THE .FHX FILE OVER USB.\n";
  $comments .= "  * THE 'print' COMMAND IS A 'cat' OF A .pcl FILE OVER USB.\n";
  $comments .= "  * IF A 'coredump location' IS LISTED BELOW, YOU MAY GO TO THE WEBADDRESS TO DOWNLOAD IT\n";
  $comments .= "\n";
  $comments .= " - THE COMMAND IS LISTED, THEN THE NUMBER OF SECONDS IT TOOK TO EXECUTE\n";
  $comments .= "\n";


  if(exists($test_info{passed}) and @{$test_info{passed}})
  {
    $comments .= "--- COMPLETED COMMANDS ---\n";

    my @arr = @{$test_info{passed}};
    while(@arr)
    {
      my $test = shift(@arr);
      my $time = shift(@arr);
      $comments .= "$test => $time\n";
    }
  }
  else
  {
    $comments .= "--- NO COMMANDS WERE EXECUTED ---\n";
  }

  $comments .= "\n";

  if(exists($test_info{failed}) and @{$test_info{failed}})
  {
    $result = SiriusHub::TEST_FAIL;
    $comments .= "--- UDW COMMANDS THAT RETURNED ERROR CODES ---\n";
    my @arr = @{$test_info{failed}};
    while(@arr)
    {
      my $test = shift(@arr);
      my $time = shift(@arr);
      $comments .= "$test => $time\n";
      $problems .= "$test failed\n";
    }
  }

  # The serial output is unconditionally passed to this function, but we only want to submit
  # this to Sirius Hub if there is a failure of some kind.
  $tty_output = undef if($result eq SiriusHub::TEST_PASS);

  my ($ret,$err_str) = autotest_submit_results($hw_test_id,$result,$problems,$comments,$$tty_output,$scm_key,$rev_str);

  if($err_str)
  {
    print("**********\n");
    print("- Error reporting results to Sirius Hub!\n");
    print("- Error message: $err_str\n");
    print("**********\n");
    prompt("Error reporting results to Sirius Hub. Error output: $err_str\nWould you like to continue?",$prod,$wtr,$rdr,$s);
  }
  my %results_hash = %{$ret};
  if($results_hash{status} eq SiriusHub::JSON_SUCCESS)
  {
    print("- Sirius Hub successfully updated.\n\n");
  }
  else
  {
    print("- Sirius Hub reported errors.\n");
  }

  %test_info = ();
}

sub check_test_time($$$)
{
  my ($wtr,$rdr,$s) = @_;
  return unless(@end_time);

  if (@end_time)
  {
    @cur_time = localtime(time);
    if (defined $cur_time_has_wrapped)
    {
      if ($cur_time_has_wrapped)
      {
        if ($cur_time[2] == $end_time[0])
        {
          if ($cur_time[1] >= $end_time[1])
          {
            print("- End time reached, now exiting...\n");
            my_exit(0,$wtr,$rdr,$s);
          }
        }
        elsif ($cur_time[2] > $end_time[0])
        {
          print("- End time reached, now exiting...\n");
          my_exit(0,$wtr,$rdr,$s);
        }
      }
    }
    else
    {
      if ($cur_time[2] == $end_time[0])
      {
        if ($cur_time[1] >= $end_time[1])
        {
          print("- End time reached, now exiting...\n");
          my_exit(0,$wtr,$rdr,$s);
        }
      }
      elsif ($cur_time[2] > $end_time[0])
      {
        print("- End time reached, now exiting...\n");
        my_exit(0,$wtr,$rdr,$s);
      }
    }
  }
}

sub tty_reader($$$$)
{
  my $rdr = shift @_;
  my $start_sem = shift @_;
  my $named_pipe = shift @_;
  my $shared_buffer = shift @_;

  open(TTY_FH,">$named_pipe") or die("Could not open named pipe ($named_pipe): $!\n");
  select TTY_FH;
  $| = 1;

  Comm::read_serial($rdr,$start_sem,$shared_buffer);
}

sub create_pipe($)
{
  my $path = shift @_;

  # Check to see if pipe exists and try to create if it doesn't
  if(-e $path and not -p $path)
  {
    print("WARNING: The file $path is not a named pipe!\n".
          "Will attempt to remove and replace with named pipe\n");
    unlink($path);
    die("Could not remove $path\n") if(-e $path);
  }
  if(not -e $path)
  {
    print("WARNING: No pipe exists for output, will attempt to create one\n");
    my ($ret,$out) = command("$mkfifo $path");

    die("WARNING: Unable to create pipe.\n".
        "Error Output: $out\n") if($ret);
    print("Pipe successfully created!\n");
  }
}

sub launch_xterm
{
  my $ppid = fork();
  return(undef) unless(defined($ppid));
  if($ppid)
  {
    # Wait for the child process to start
    sleep(1);
    my $wait_attempts = 5;
    while($wait_attempts > 0)
    {
      my @output=`ps -o pid --ppid $ppid`;
      if(defined($output[1]))
      {
        my $pid = $output[1];
        chomp($pid);
        push(@children,$pid);
        return($pid);
      }
      sleep(1);
      $wait_attempts -= 1;
    }
    kill('TERM', $ppid);
    waitpid($ppid,0);
    return(undef);
  }
  else
  {
    # This is the child process
    setpgrp;
    exec($xterm, "-hold", "-si", @_);
  }
}

sub sol_tty_mux
{
  my $in_pipe = shift @_;
  my $err_file = shift @_;

  my $pid = fork();
  return(undef) unless(defined($pid));
  if($pid)
  {
    push(@children,$pid);
    return $pid;
  }
  else
  {
    # This is the child process
    setpgrp;
    open(STDIN, "<", "/dev/null");
    open(STDOUT, ">", $in_pipe);
    open(STDERR, ">", $err_file);
    select STDERR; $| = 1;
    select STDOUT; $| = 1;
    exec("/sirius/tools/bin/sol_tty_mux", @_);
  }
}
