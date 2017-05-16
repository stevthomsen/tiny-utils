#!/usr/bin/perl -w
package Comm;

use IO::File;
use IO::Handle;
use IO::Pipe;
use IO::Select;
use IO::Socket::UNIX;
use Fcntl;
use POSIX qw(termios_h);
use strict;

use Exporter;
use vars qw(@ISA @EXPORT);
@ISA=qw(Exporter);
@EXPORT = qw(open_socket close_socket open_tty close_tty udws_direct read_serial read_parse_serial);

my $debug = undef;
#$debug = 1;

### CONSTANTS ###
use constant FALSE => 0;
use constant TRUE => 1;
use constant ERROR => 1;
use constant SUCC => 0;
use constant FINISHED_STATE => 'IDLE';

### CONSTANT STRINGS ###
use constant LINE_TERMINATOR => "\n\n";
use constant END_SEQUENCE => qr/[-elx]>/;
use constant BAUDSPEED => 0010002;

### CONSTANT TIMES (all in seconds) ###
use constant SERIAL_WAIT => 1;
use constant READ_TIMEOUT => 5;
use constant WRITE_TIMEOUT => 5;
use constant TRUST_JOB_TRACKING => 1;

sub open_socket($$);
sub close_socket($$$);
sub open_tty($$);
sub close_tty($$$);
sub udws_direct($$$$;$$);
sub parse_udw($$$$);

my %Printable = (
  ( map { chr($_), unpack('H2', chr($_)) } (0..255) ),
  ( "\\"=>'\\', "\r"=>'r', "\n"=>'n', "\t"=>'t', ),
  ( map { $_ => $_ } ( '"' ) )
);

# Hash to store jobs that may have started right when UDW command was processed
my %jobs = ();

sub printable($)
{
  local $_ = ( defined $_[0] ? $_[0] : '' );
  s/([\r\n\t\\\x00-\x1f\x7F-\xFF])/ '\\' . $Printable{$1} /gsxe;
  return $_;
}

# ARGS:
#		device to open (eg. $config_dir/$prod_dir/tty.sock)
#		$s (the IO::Select object to add the filehandle to)
# RETS:
#		$RETURN - was able to open the device
#		$OUTPUT - If any errors then message is here
#		$WTR - The file handle to write to this device
#		$RDR - The file handle to read from this device
sub open_socket($$)
{
	my $device = shift @_;
	my $s = ${shift @_};

	print("- Open socket device -> $device\n") if($debug);

	my $socket = IO::Socket::UNIX -> new(Type => SOCK_STREAM, Peer => $device);
	return(ERROR,"Could not open $device") unless($socket);

	print("- socket -> $socket\n") if($debug);

	$socket -> autoflush(1);

	## Add the file handle to the select object
	$s -> add($socket);

	## test the connection
	my ($result,$cmd,$udw_return,$out) = udws_direct("",$socket,$socket,\$s);

	#TODO.. we need this to pick up some units, but take long
	#time when nothing is connected  :-(
	#could not complete the cmd..
	if($result == ERROR or $udw_return == ERROR)
	{
		#try one more time
		($result,$cmd,$udw_return,$out) = udws_direct("",$socket,$socket,\$s);
	}

	return (ERROR,$out,$socket,$socket) if($result == ERROR or $udw_return == ERROR);
	return ($result,$out,$socket,$socket);
}

# ARGS:
#		device to open (eg. /dev/ttyUSB0)
#		$s (the IO::Select object to add the filehandle to)
# RETS:
#		$RETURN - was able to open the device
#		$OUTPUT - If any errors then message is here
#		$WTR - The file handle to write to this device
#		$RDR - The file handle to read from this device
sub open_tty($$)
{
	my $device = shift @_;
	my $s = ${shift @_};

	print("- Open TTY device -> $device\n") if($debug);

	# Create a new fh to the device
	my $wtr = IO::File -> new();
	my $rdr = IO::File -> new();

	print("- wtr -> $wtr\n") if($debug);
	print("- rdr -> $rdr\n") if($debug);

	## Open comminication with the device
	sysopen($wtr, $device, O_WRONLY|O_NONBLOCK) or return(ERROR,"Could not open $device: $!",undef);
	sysopen($rdr, $device, O_RDONLY|O_NONBLOCK) or return(ERROR,"Could not open $device: $!",undef);

	## Configure the serial port
	config_serial($wtr);
	config_serial($rdr);

	$wtr->autoflush(1);
	$rdr->autoflush(1);

	## Add the file handle to the select object
	$s -> add($wtr);
	$s -> add($rdr);

	## test the connection
	my ($result,$cmd,$udw_return,$out) = udws_direct("",$wtr,$rdr,\$s);

	#TODO.. we need this to pick up some units, but take long
	#time when nothing is connected  :-(
	#could not complete the cmd..
	if($result == ERROR or $udw_return == ERROR)
	{
		#try one more time
		($result,$cmd,$udw_return,$out) = udws_direct("",$wtr,$rdr,\$s);
	}

	return (ERROR, $out, $wtr,$rdr) if($result == ERROR or $udw_return == ERROR);
	return ($result,$out,$wtr,$rdr);
}


# ARGS:
#		cmd to execute (eg. "\n" or "bio.project");
#		wtr filehandle ptr
#		rdr filehandle ptr
#		Select object
# RETS:
#		SUCCESS/FAILURE (eg. was able to send the command ok,)
#		CMD executed
#		RETURN  if the command returned successful or not
#		OUTPUT output from the command
sub udws_direct($$$$;$$)
{
	my $cmd = shift @_;
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $select = ${shift @_};
	my $tty_buffer = shift @_;
	my $tty_output = shift @_;

	#we send a blank string to check the connection
	#but for everything else, make sure we prefix with udws
	$cmd = "udws \"$cmd\"" if($cmd);

	my $write_wait_attempts = 6;

	#make sure the file handle is valid
	return(ERROR,$cmd,ERROR,"Not passed a valid WTR file handle") unless( $select -> exists ($wtr));
	return(ERROR,$cmd,ERROR,"Not passed a valid RDR file handle") unless( $select -> exists ($rdr));

	print("- About to start finding writeable fh\n") if($debug);

	LOOP: while($write_wait_attempts != 0)
	{
		#make sure the file handle is ready to write to
		my @writeable = $select->can_write(WRITE_TIMEOUT);

		for my $write (@writeable)
		{
			if($wtr == $write)
			{
				print("- File handle ready for writing!\n") if($debug);
				last LOOP;
			}
			else
			{
				print("- File handle not ready for writing yet\n") if($debug);
				sleep(SERIAL_WAIT);
			}
		}

		$write_wait_attempts -= 1;
	}

	return(ERROR,$cmd,ERROR,"Could not get a writeable lock on filehandle") unless($write_wait_attempts);

	print("- Found a write lock on the correct handle\n") if($debug);

	### READY TO WRITE! ###
	#make sure the $cmd ends with a newline
	chomp($cmd);

	### SEND THE COMMAND ###
	print("- Sending command: <$cmd>\n") if($debug);
	my $ret = $wtr -> syswrite($cmd.LINE_TERMINATOR);
	return(ERROR,$cmd,ERROR,"Write to serial failed: $!") unless(defined($ret));

	### READ AND PARSE SERIAL OUTPUT
	# RETURN (RET, CMD, UDW_RET, OUT, ASSERT)
	return(read_parse_serial($wtr,$rdr,$select,$cmd,undef,$tty_buffer,$tty_output));
}

# SUCCESS/FAILURE (Command worked)
# CMD EXECUTED
# RET
# OUTPUT
# ASSERT
sub parse_udw($$$$)
{
	my $cmd = shift @_;
	my $raw_output = shift @_;
	my $wait_function = shift @_;
	my $tty_buffer = shift @_;

	my $end_sequence = END_SEQUENCE;

	#the first line is always the echo of the command we gave
	my @lines = split(/\n/,$raw_output);

	my $parsed_output = "";
	my $return = 0;
	my $assert_flag = undef;
	my $command_error = FALSE;

	for my $line (@lines)
	{
		print("  - Parsing: '$line'\n") if($debug);

		if($line =~ /^(.*?);?udws\(\) returns (\d+)/)
		{
			$parsed_output .= $1;
			$return = $2;
		}
		elsif($line =~ /bad command/ or $line =~ /don't understand/)
		{
			$parsed_output .= $line."\n";
			$command_error = TRUE;
		}
		elsif($line =~ /Waiting for SREC data/)
		{
			$parsed_output .= $line."\n";
		}
		elsif($line =~ /^\*\*\*\s*ASSERT:/ or $assert_flag)
		{
			#ASSERT OCCURRED! get the assert output and send back
			$assert_flag = 1;

			#strip out the *** and attached that to assert output
			$parsed_output .= $line."\n" if($line =~ /^\*\*\*/);
		}
		elsif($line =~ /^${end_sequence}$/)
		{
			chomp($parsed_output);

			#check for errors in the return string
			$return = ERROR if($command_error);

			return(SUCC,$cmd,$return,$parsed_output);
		}
		elsif($line =~ /(can't allocated ID)/) #bad things, don't want to see this -- and yes there is a 'd' on the end of allocate
		{
			#don't know what to do, printer hung in "now printing..."
			#had tried printing with out of ink several times and now does this
			$parsed_output .= $1;
		}
	}

	#if not caught in a case above, return what we have so far
	return(SUCC,$cmd,ERROR,$parsed_output,1) if($assert_flag);
	return(SUCC,$cmd,SUCC,$parsed_output,0) if($wait_function);

	#if not waiting for clean serial and we are using the the reader thread, we didn't see the end sequence
	#so we can assume serial comm isn't working
	#note this is true even if serial output is available (i.e. serial output during reflash, but can't communicate)
	return(SUCC,$cmd,ERROR,$parsed_output) unless(defined($tty_buffer));
	return(ERROR,$cmd,ERROR,$parsed_output);
}

sub close_socket($$$)
{
	my $socket = shift @_;
	shift @_; # Ignore duplicate
	my $s_ptr = shift @_;
	my $s = ${$s_ptr} if($s_ptr);

	print("- Close socket -> $socket\n") if($debug);

	if($s and ref($s) =~ /IO::/)
	{
		#is it defined in $s?
		$s -> remove($socket) if($s -> exists($socket));
	}

	#close the handle
	close($socket) if($socket);
	return;
}

sub close_tty($$$)
{
	my $wtr = shift @_;
	my $rdr = shift @_;
	my $s_ptr = shift @_;
	my $s = ${$s_ptr} if($s_ptr);

	print("- Close TTY: wtr -> $wtr\n") if($debug);
	print("- Close TTY: rdr -> $rdr\n") if($debug);

	if($s and ref($s) =~ /IO::/)
	{
		#is it defined in $s?
		$s -> remove($wtr) if($s -> exists($wtr));
		$s -> remove($rdr) if($s -> exists($rdr));
	}

	#close the handle
	close($wtr) if($wtr);
	close($rdr) if($rdr);
	return;
}

sub read_serial($$$)
{
	my $tty = shift @_;
	my $semaphore = shift @_;
	my $tty_buffer = shift @_;

	print("Reader thread starting\n") if($debug);

	print("Configuring serial for live data...\n") if($debug);
	config_serial($tty,TRUE);

	# Set up a pipe to signal exit
	my $rdr = IO::Handle -> new();
	my $wtr = IO::Handle -> new();
	my $pipe = IO::Pipe -> new($rdr, $wtr);

	# Recieving the STOP signal will write to the pipe to signal exit
	$SIG{'STOP'} = sub
	{
		print("\n\nReceived STOP signal!\n") if($debug);
		$wtr -> syswrite("\0");
	};

	# Signal semaphore that reader is ready
	$semaphore -> up(1);

	my $string = "";

	# Create select object to wait on file events
	my $select = IO::Select -> new();
	$select -> add($tty);
	$select -> add($rdr);

	print "Now displaying live serial data:\n\n";

	READ_LOOP: while(TRUE)
	{
		my @ready = $select -> can_read(1);
		next unless(@ready);
		foreach (@ready)
		{
			#print("Handle $_ ready for reading\n");
			last READ_LOOP if($_ == $rdr);
		}

		my $out = "";
		$tty -> sysread($out,1);

		print $out;
		$string .= $out;
		if($out eq "\n")
		{
			lock($tty_buffer);
			push(@$tty_buffer,$string);
			$string = "";
		}
	}

	print("Reader thread exiting\n") if($debug);
}

sub read_parse_serial($$$$;$$$)
{
	my ($wtr,$rdr,$select,$cmd,$max_read_attempts,$tty_buffer,$tty_output) = @_;

	my $read_wait_attempts = 6;
	my $end_sequence = END_SEQUENCE;
	my $timeout = 300;
	my $wait_function = 1 if($max_read_attempts);
	$max_read_attempts = 10 unless($max_read_attempts);

	#turn on job tracking by default
	my $job_tracking = TRUST_JOB_TRACKING;

	#if tty_buffer isn't defined, we are reading from this function and not from the shared array the reader thread manages
	unless(defined($tty_buffer))
	{
		#make sure the file handle is valid
		return(ERROR,$cmd,ERROR,"Not passed a valid WTR file handle") unless( $select -> exists ($wtr));
		return(ERROR,$cmd,ERROR,"Not passed a valid RDR file handle") unless( $select -> exists ($rdr));

		LOOP2: while($read_wait_attempts != 0)
		{
			#make sure the file handle is ready to write to
			my @readable = $select -> can_read(READ_TIMEOUT);

			for my $read (@readable)
			{
				if($rdr == $read)
				{
					print("- File handle ready for reading!\n") if($debug);
					last LOOP2;
				}
			}
			$read_wait_attempts -= 1;
			sleep(SERIAL_WAIT);
		}

		return(ERROR,$cmd,ERROR,"Could not get a readable lock on filehandle") unless($read_wait_attempts);
	}

	print("- Ready to start reading\n") if($debug);

	### READY TO READ NOW ###
	my $string = "";
	#read as long as the timeout hasn't expired yet
	my $start_time = time();
	my $read_attempts = $max_read_attempts;
	my $assert_count = 0;

	#TODO
#	print("\n") if($wait_function);

	# Hash is to hold all the jobs that we
	# see kicked off after a udw command
	# we'll see something like
	#	Job State Transition: <JOB_NAME>, SUID <suid>, (<SUID>) '<OLD_STATE>' = '<NEW_STATE>'
	# the hash will look like $hash{JOB_NAME SUID} = <NEW_STATE>
	# then when all the jobs in the hash have reached the IDLE state we know command
	# has completed!
	my %job_tracker = %jobs;
	%jobs = ();
	my $idle_job_wait = 30;
	my $job_wait = 90;
	my $last_time_job_turned_idle = 0;
	my $last_time_got_job_info = 0;
	my $total_job_time = 0;
	my $output = undef;
	my $read_something = undef;
	my $blank_cmd = 1 unless($cmd);

	if($wait_function and $job_tracking and %job_tracker)
	{
		foreach(keys(%job_tracker)) { print("("); }
		$last_time_got_job_info = time;
	}

	ATTEMPT: while($read_attempts != 0)
	{
		if($wait_function)
		{
			$total_job_time = time - $start_time;
			if($total_job_time > $timeout)
			{
				print("  - Hit timeout in wait function\n") if($debug);
				return(SUCC, $cmd, ERROR, "Hit timeout limit", undef);
			}
		}

		print(" - Read attempt\n") if($debug);

		#if tty_buffer is defined, we read serial data from the shared array filled by the reader thread
		#otherwise we will get a line from serial directly
		if(defined($tty_buffer))
		{
			lock($tty_buffer);
			$output = shift(@$tty_buffer);
		}
		else
		{
			#got these from IO::Handle, not sure if they work, but worth a try  :-)
			$rdr->flush();
			$rdr->sync();
			$output = $rdr -> getline();
		}

		unless($output)
		{
			#TODO
			print("-") if($wait_function and not $read_something);
			$read_something = undef;
		}
		else
		{
			$$tty_output .= $output if(defined($tty_output));

			print("  - Just read: '".printable($output)."' (".length($output).")\n") if($debug);

			#get every kind of newline/space char out of there!
			$output =~ s/\015//g;
			$output =~ s/\012//g;
			$output =~ s/^\s+//;
			$output =~ s/\s+$//;
			$output =~ s/\n$//;

			print("  - Cleaned output: '".printable($output)."' (".length($output).")\n") if($debug);

			#make sure we're not grabbing the command being echoed back
			#for blank command, echo may not have -> if prior serial wiped it out, so it will just be newline
			if($blank_cmd and (not $output or $output =~ /^${end_sequence}$/))
			{
				$blank_cmd = undef;
				next;
			}
			next if($cmd and ($output =~ /^${end_sequence}\s+$cmd/ or $output =~ /^$cmd$/));

			$string .= $output."\n" if($output);
			#check for terminating sequence in last line we read
			#IF we're not waiting
			#  because if we are waiting for clean output, then doesn't
			#  matter how many end_sequences we see..
			last ATTEMPT if($output =~ /^${end_sequence}$/ and not $wait_function);

			$assert_count += 1 if($output =~ /^\*\*\*\s*ASSERT:/);
			last ATTEMPT if($assert_count > 1);

			# Check for 'Waiting for SREC data' if we are reflashing
			last ATTEMPT if($wait_function and $cmd and $cmd =~ /srec_download/ and $output =~ /Waiting for SREC data/);

			# eg. Job State Transition: PJL_KHEOPS (1097) 'READY' -> 'RUNNING'
			# we could require that jobs being put into %job_tracker start in the IDLE state
			# but seems ok for now..
			if($job_tracking and (
					$output =~ /Job State Transition: (\S+), SUID \d+, \((\d+)\) '(\S+)' -> '(\S+)'/
					or
					$output =~ /Job State Transition: (\S+) \((\d+)\) '(\S+)' -> '(\S+)'/))
			{
				print("JOB '$1 $2' FROM ".$job_tracker{"$1 $2"}." (read $3) => $4\n") if(exists($job_tracker{"$1 $2"}) and $debug);
				print("NEW JOB '$1 $2' FROM $3 => $4\n") if(exists($job_tracker{"$1 $2"}) and $debug);

				$job_tracker{"$1 $2"} = $4;
				$last_time_got_job_info = time;
				$last_time_job_turned_idle = time if($4 eq FINISHED_STATE);

				if($wait_function)
				{
					if($3 eq "IDLE")
					{
						print("(");
					}
					elsif($4 eq "IDLE")
					{
						print(")");
					}
					else
					{
						print("|");
					}
				}
				else
				{
					# Not waiting for this job, so store it in the global hash
					$jobs{"$1 $2"} = $4;
				}
			}

			#TODO
			print("+") if($wait_function and not $read_something);
			$read_something = 1;

			#if we're still getting data, then extend the read_attempts
			$read_attempts = $max_read_attempts;
		}

		# Check if we have all the jobs in state 'IDLE'
		if($job_tracking and %job_tracker)
		{
			my $all_jobs_finished = "true";
			map{ $all_jobs_finished = undef if($job_tracker{$_} ne FINISHED_STATE) } keys(%job_tracker);
			if($all_jobs_finished)
			{
				#have to wait at least $idle_job_wait seconds since last job
				# turned idle before moving on.
				if($last_time_job_turned_idle and (time() - $last_time_job_turned_idle < $idle_job_wait))
				{
					#might want a debug
					print("   - All jobs are done, but need at least $idle_job_wait seconds before can exit with all jobs idle\n") if($debug);
				}
				else
				{
					print("\n  - FOLLOWING JOBS HAVE COMPLETED:\n");
					map{ print("      $_ : $job_tracker{$_}\n") } keys(%job_tracker);
					last;
				}
			}
			# We have been keeping track of jobs, but they are not
			 # all marked idle. But in case it has been more than $last_time_got_job_info
			 # since we got any job information then quit out of loop
			elsif( $last_time_got_job_info and ( time() - $last_time_got_job_info > $job_wait))
			{
					print("\n  - It has been more than $job_wait seconds since we received any job information. Unfinished jobs are listed below:\n");
					map{ print("      $_ : $job_tracker{$_}") if($job_tracker{$_} ne FINISHED_STATE) } keys(%job_tracker);
					last;
			}
		}
		next if($read_something);
		sleep(SERIAL_WAIT);

		# just keep looping if we are tracking jobs and we have read something from 'JOB STATE TRANSITIONS'
		$read_attempts -= 1 unless(TRUST_JOB_TRACKING and %job_tracker);

	}

	if($wait_function)
	{
		print("\n");
	}
	elsif($job_tracking and %jobs)
	{
		# Remove jobs that may have completed from the global list
		foreach(keys(%jobs))
		{
			delete $jobs{$_} if($jobs{$_} eq FINISHED_STATE);
		}
	}

	#return if we have an assert
	#return(SUCC, $cmd, ERROR, $string, 1);
		#if($string =~ /\*\*\*\s*ASSERT:/);

#	print("- Finished reading. Full Output: $string\n") if($debug);
	return parse_udw($cmd,$string,$wait_function,$tty_buffer);
}

sub config_serial($;$)
{
	my $FH = shift @_;
	my $unbuffered_read = shift @_;

	my $termios = POSIX::Termios->new();
	my $att = $termios -> getattr(fileno($FH));
	return unless($att);

	#SETTING THE FOLLOWING FLAGS:
	# C FLAGS
	#  FALSE: -parenb -parodd -cstopb
	#  TRUE: cs8 hupcl cread clocal
	# I FLAGS:
	#  FALSE: -ignbrk -brkint -ignpar -parmrk -inpck -istrip -inlcr -igncr -ixoff
	#  TRUE:  icrnl ixon
	# O FLAGS:
	#  FALSE: OPOST
	# L FLAGS:
	#  FALSE:  -echo -echonl -noflsh -tostop -icanon
	#  TRUE: isig iexten echoe echok

	#SET THESE CFLAG VALUES TO TRUE
#	$termios->setcflag( $c_cflag | &POSIX::CS8 | &POSIX::HUPCL | &POSIX::CREAD | &POSIX::CLOCAL);
	#SET VALUES CFLAG TO FALSE
#	$termios->setcflag( $c_cflag & ~(&POSIX::PARENB | &POSIX::PARODD | &POSIX::CSTOPB));

	#SET THESE IFLAG VALUE TO TRUE
#	$termios->setiflag( $c_iflag | &POSIX::ICRNL);
	#SET THESE IFLAG VALUES TO FALSE
#	$termios->setiflag( $c_iflag & ~(&POSIX::IXON | &POSIX::IGNBRK | &POSIX::BRKINT | &POSIX::IGNPAR | &POSIX::PARMRK | &POSIX::INPCK | &POSIX::ISTRIP | &POSIX::INLCR | &POSIX::IGNCR | &POSIX::IXOFF) );

	#SET THIS OFLAG VALUE TO TRUE
	#$termios->setoflag( $c_oflag | &POSIX::OPOST);
	# USB WORKING
#	$termios->setoflag( $c_oflag & ~(&POSIX::OPOST));

	#SET THESE L VALUE TO TRUE
	#$termios->setlflag( $c_lflag | &POSIX::ISIG | &POSIX::ICANON | &POSIX::IEXTEN | &POSIX::ECHOE | &POSIX::ECHOK);
	#$termios->setlflag( $c_lflag & ~( &POSIX::ECHO | &POSIX::ECHONL | &POSIX::NOFLSH | &POSIX::TOSTOP));

	# USB WORKING
#	$termios->setlflag( $c_lflag | &POSIX::ISIG);
#	$termios->setlflag( $c_lflag & ~(&POSIX::ICANON | &POSIX::ECHO | &POSIX::ECHOE | &POSIX::ECHOK | &POSIX::ECHONL | &POSIX::NOFLSH | &POSIX::TOSTOP | &POSIX::IEXTEN));

	#SET THESE CFLAG VALUES TO TRUE
	$termios->setcflag(POSIX::CS8 | POSIX::CREAD | POSIX::HUPCL | POSIX::CLOCAL);
	#SET VALUES CFLAG TO FALSE
#	$termios->setcflag($c_cflag & ~(POSIX::PARENB | POSIX::PARODD | POSIX::CSTOPB));

	#SET THESE IFLAG VALUE TO TRUE
#	$termios->setiflag(0) if($flag == 0);
	$termios->setiflag(POSIX::IGNCR);# if($flag == 1 or $flag == 2);#POSIX::IXON | POSIX::IXOFF);
	#SET THESE IFLAG VALUES TO FALSE
#	$termios->setiflag(0);#$c_iflag & ~(POSIX::IGNBRK | POSIX::BRKINT | POSIX::IGNPAR | POSIX::PARMRK | POSIX::INPCK | POSIX::ISTRIP | POSIX::INLCR | POSIX::IGNCR | POSIX::ICRNL | POSIX::IUCLC | POSIX:IXON | POSIX::IXANY | POSIX::IXOFF | POSIX::IMAXBELL | POSIX::IUTF8));

	#SET THIS OFLAG VALUE TO TRUE
	#$termios->setoflag( $c_oflag | &POSIX::OPOST);
	# USB WORKING
	$termios->setoflag(0);#$c_oflag & ~(POSIX::OPOST | POSIX::OLCUC | POSIX::ONLCR | POSIX::OCRNL | POSIX::ONOCR | POSIX::ONLRET | POSIX::OFILL | POSIX:OFDEL));

	#SET THESE L VALUE TO TRUE
 	#$termios->setlflag( $c_lflag | &POSIX::ISIG | &POSIX::ICANON | &POSIX::IEXTEN | &POSIX::ECHOE | &POSIX::ECHOK);
	#$termios->setlflag( $c_lflag & ~( &POSIX::ECHO | &POSIX::ECHONL | &POSIX::NOFLSH | &POSIX::TOSTOP));

	# USB WORKING
	$termios->setlflag(POSIX::ICANON) unless($unbuffered_read);
	$termios->setlflag(0) if($unbuffered_read);#POSIX::ISIG);#POSIX::ICANON);# | POSIX::IEXTEN); #POSIX::IEXTEN | POSIX::ICANON);
#	$termios->setlflag(0);# $c_lflag & ~(POSIX::ISIG | POSIX::ICANON | POSIX::ECHOE | POSIX::ECHOK | POSIX::ECHO | POSIX::ECHONL | POSIX::NOFLSH | POSIX::TOSTOP | POSIX::IEXTEN));

	$termios->setospeed(BAUDSPEED);
	$termios->setispeed(BAUDSPEED);

	#set values immediatly
	$termios->setattr(fileno($FH), POSIX::TCSAFLUSH);
	$termios->setattr(fileno($FH), POSIX::TCSANOW);
	return;
}

1;
