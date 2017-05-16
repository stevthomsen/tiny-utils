#!/bin/bash

version="1.13"

#set -x		# Echo all lines as expanded/executed
#set -n		# Expand/parse but do not execute

##
## branch
##
#
#	Written by:	Joe Eckardt
#	Written:	06 Jun 16
#	Updated: 	27 Jun 16
#
#
# Auto-branch for Limo and Bugatti "weekly" builds
#


#
# Get our name and path for future use
#
    myname=${0##*/}		# remove any path
    myname=${myname%.*}		# remove any ext

    if [[ $0 = */* ]] ; then
	mypath=${0%/*}		# remove prog name leaving path
    else
	mypath="."		# no path at all, assume cwd
    fi


###########
###########
##
## Configurable parameters
##

#
# Email parameters
#
email_from="joe.eckardt@hp.com"
email_to="sirius.firmware@hp.com;sirius.fw.partners@hp.com"	# semi-colon separated list
email_debug_to=$email_from
email_cc=""
email_bcc=""
email_debug_subject="[TESTING - PLEASE IGNORE] "		# subject prefix if debugging
email_admins="joe.eckardt@hp.com ktang@hp.com"			# space separated list
email_debug_admins=$email_from
email_addsha_to="ktang@hp.com;joe.eckardt@hp.com;ronald.cardin@hp.com;andrew.walker5@hp.com"	# semi-colon separated
email_addsha_subj="Please%20cherry-pick%20this%20sha%20into%20the%20release!"			# use %20 for spaces!
email_signature="Joe Eckardt"

#
# Directory pointers
#
git_repo="/work/sirius"					# a git repository to use, will not be modified
logdir="/work/logs"					# directory where logs are written
ctrldir="/work/cronctrl"				# directory for control files
tempdir="/tmp"						# temp directory
note="note"						# base name of note file (a .html extension will be added)
schedule="schedule"					# base name of schedule file (a .html/.jpg will be added)
kept_email="letter.txt"					# name to use for saved email
ctrllocal="cronctrl.local"				# name of semaphore file to use local directory (for testing)

#
# Path add-ons
#
PATH="/sirius/tools/bin:/bin:/usr/bin:$PATH"		# minimum path required

#
# Default values
#
majver="002"						# default major version

##
##
########### End of Configurable Parameters ###########
######################################################

#
# Some local constants and pointer
#
    MINARGS=1		# minumum number of required args, excluding switches
    MAXARGS=2		# maximum number of args allowed, excluding switches (-1=no max)
    OPERATION="branch"	# string used in disable control file name

#
# Initialize local variables
#
    DEBUG=0
    exitcode=0		# "successful" exit status as default
    verbose=0		# non-verbose by default
    sendmail=1		# send publish email, def=true
    engine=0		# flag whether or not to include engine in the build
    keep=0		# don't delete the temp files
    force=0		# ignore all control files
    send_saved_email=0	# send the saved publication email

    letter="${tempdir}/$myname$$.tmp"


#####################
# Support Functions #
#####################

#
# Usage message
#
function usage
{
    if [[ $verbose -ge 1 ]] ; then
	echo "v$version"
    fi
    echo ""
    echo "Usage: ${myname} [-help] [-debug] [-send_saved_email] [-debug_email] [-noemail] [-keep_email] [-force] <release_group> [<iteration>]"
    echo ""
    if [[ $verbose -ge 1 ]] ; then
	echo "    -keep_email	     Keep a copy of the generated email in the local directory when done"
	echo "    -send_saved_email  Send the email kept from the last publication ONLY"
	echo "    -noemail           Suppress sending announcement email, but still sends admin email"
	echo "    -force             Ignore all control files"
    fi
    exit $exitcode
}


################
# Main Program #
################

#
# Process command line switches
#
    if [[ $# -gt 0 ]] ; then
	while [[ $1 = -* ]] ; do
	    case $1 in
		-h*|--h*)	
		    #
		    # -help
		    #
		    verbose=1		# force a long usage
		    exitcode=0
		    usage
		    ;;

		-debuge*|-debug_e*)
		    #
		    # -debug_email
		    #
		    # Use a special set of email addresses instead of the production
		    # ones
		    #
		    email_to=$email_debug_to
		    email_admins=$email_debug_admins
		    shift
		    ;;

		-debug)
		    #
		    # -debug
		    #
		    # Specifically, don't actually do the branching, but other things
		    # may also be effected
		    #
		    email_to=$email_debug_to
		    email_admins=$email_debug_admins
		    DEBUG=1
		    shift
		    ;;

		-s)
		    #
		    # -send
		    #
		    # Send saved email from last branching
		    #
		    send_saved_email=1
		    shift;
		    ;;

		-noe*)
		    #
		    # -noemail
		    #
		    # Disable sending the notification email
		    #
		    sendmail=0
		    shift
		    ;;

		-k*)
		    #
		    # -keep
		    #
		    # Copy the temp email to the current directory
		    #
		    keep=1
		    shift
		    ;;

		-f*)
		    #
		    # -force
		    #
		    # Ignore all control files
		    #
		    force=1
		    shift
		    ;;

		*)
		    #
		    # Unrecognized switch
		    #
		    echo "${myname}: Unknown switch '$1'"
		    echo ""
		    exitcode=1		# exitcode 1: Invocation error: unknown switch or illegal command line argument
		    shift
		    usage
		    ;;
	    esac
	done
    fi

#
# See if we have the correct number of arguments left after
# having processed and removed all of the switchesdow=`date +%a | tr '[:upper:]' '[:lower:]'`
#
    if [[ $# -lt $MINARGS || ( $MAXARGS -ge 0 && $# -gt $MAXARGS ) ]] ; then
	exitcode=2
	usage
    fi

#
# Process command line args
#
    #
    # First argument is required, is the release group
    #
    relgrp=$1

    #
    # Second argument is optional, and is the release group
    #
    if [[ $# -ge 2 ]] ; then
	iteration=$2
    else
	iteration=0		# if no iteration given, then default to 0
    fi


##################
#
# The real work...
#

    #
    # Add the release group name to the front of the email name to make sure
    # it's unique in case we save two on the same day
    #
    kept_email="${relgrp}_${kept_email}"

    #
    # If we've been asked to send a previously saved email, do it now, then
    # exit
    #
    if [[ $send_saved_email -ge 0 ]] ; then
	#
	# Make sure we have a saved email to send
	#
	if [[ -e $logdir/$kept_email ]] ; then
	    #
	    # Send it
	    #

	    # Probably should do this in a subroutine, but for now it's inline
	    if [[ $DEBUG -ge 1 ]] ; then
		echo "DEBUG: not sent: sendmail -F \"$email_from_name\" -f \"$email_from\" $email_to < $logdir/$kept_email"
	    else
		echo "Sending saved notification email..."
		sendmail -f "$email_from" -t < $logdir/$kept_email
		echo "Sent"
		echo ""
		rm $logdir/$kept_email
	    fi
	    exit
	else
	    #
	    # No email to send
	    #
	    echo "${myname}: No saved email to send at '$logdir/$kept_email'" 
	    exit
	fi
    fi

    #
    # Remove any old saved email so we don't confuse things
    #
    if [[ -e $logdir/$kept_email ]] ; then
	rm $logdir/$kept_email
    fi

    #
    # See if we're supposed to use the local directory for the control and log
    # files
    #
    if [[ -e "./$ctrllocal" ]] ; then
	ctrldir="."
    fi

    #
    # Get our current directory
    #
    CWD=`pwd`

    #
    # Get the current date/time for a timestamp
    #
    timestamp=`date +%m/%d/%Y\ @\ %r\ %Z`
    dow=`date +%a | tr '[:upper:]' '[:lower:]'`

    #
    # Set up the log file
    #
    if [[ -e "./$ctrllocal" ]] ; then
	logfile="./${myname}_${relgrp}.log"
    else
	logfile="${logdir}/${myname}_${relgrp}.log"
    fi

    #
    # Figure out whether we include engine or not (currently based upon iteration number)
    #
    if [[ $iteration -eq 0 ]] ; then
	engine=-1		# iteration 0 - no mention of engine
    elif [[ $iteration -eq 1 ]] ; then
	engine=0		# iteration 1 - no engine
    elif [[ $iteration -eq 2 ]] ; then
	engine=1		# iteration 2 - engine
    else
	engine=1		# iteration 3+ - engine
    fi

    #
    # Create the header for the logfile
    #
    echo "Subject: Autobuild: branch $relgrp $bldnum iteration $iteration on $timestamp" > $logfile
    echo ""							>> $logfile
    echo "***** branch: $timestamp *****"			>> $logfile
    echo ""							>> $logfile
    if [[ $DEBUG -ge 0 ]] ; then echo "DEBUG: ***** branch: $timestamp *****"; fi

    if [[ $DEBUG -ge 0 ]] ; then
	echo "DEBUG: myname = $myname" 				| tee -a $logfile
	echo "DEBUG: version = v$version" 			| tee -a $logfile
	echo "DEBUG: CWD = $CWD" 				| tee -a $logfile
	echo "DEBUG: HOME = $HOME" 				| tee -a $logfile
    fi
    
    #
    # See if we're disabled
    #
    if [[ $force -eq 0 &&
	  ( -e "$ctrldir/__all_disable__" ||
            -e "$ctrldir/__${relgrp}_disable__" ||
            -e "$ctrldir/__${OPERATION}_disable__" ||
	    -e "$ctrldir/__${OPERATION}_${relgrp}_disable__" ||
	    -e "$ctrldir/__${OPERATION}_${relgrp}_${dow}_disable__" ) ]] ; then
	#
	# Branching disabled
	#
	echo "${myname}: *** Branching disabled by control file ***"
	echo ""							>> $logfile
	echo "*** Branching disabled by control file ***"	>> $logfile
	echo ""							>> $logfile
	if [[ $DEBUG -ge 1 ]] ; then echo "DEBUG: *** Branching disabled by control file ***"; fi
    else
	#
	# Branching enabled
	#

    ### This else is closed just before the log file is sent ###

    

    #
    # Compute build number based upon the current week number
    #
    week=`date +%y%W`
    bldnum="$majver.`expr $week + 1`"

    #
    # Perform the actual branching
    #
    if [[ $DEBUG -ge 1 ]] ; then
	echo ""							>> $logfile
	echo "NOT RUN: shr.rb create_branch $relgrp vcd" 	>> $logfile
	echo ""							>> $logfile
	if [[ $DEBUG -ge 1 ]] ; then echo "DEBUG: NOT RUN: shr.rb create_branch $relgrp vcd"; fi
    else
	echo ""							>> $logfile
	shr.rb create_branch $relgrp vcd 			>> $logfile
	echo ""							>> $logfile
    fi

    #
    # Sleep for half a minute to give git time to settle before we make 
    # inquires # against the new branch. (This is to hopefully address 
    # the problem of the branch name not always being returned on the 
    # next query below.)
    #
    sleep 30		

    #
    # Get the branch name and sha
    #
    # Method 1:
    #    branch_name=`git branch -r | grep origin/z_rb_${relgrp}_1 | tail -1`
    #    sha=`git log $branch_name | head -1 | sed "s/.* //"`
    #
    #
    # Method 2:
    # 	git fetch -q && git for-each-ref --count=1 --sort=-refname refs/remotes/origin/z_rb_limo_[1-9]* --format='%(refname:short):%(objectname)'
    #
    # Returns:
    #	origin/z_rb_limo_1624_160606_173004:40545aa32df5cdcd892f3a0d90b3bb435a0ccf19
    #
    pushd $git_repo 2>&1 > /dev/null
    branch_name=`git fetch -q && git for-each-ref --count=1 --sort=-refname refs/remotes/origin/z_rb_${relgrp}_[1-9]* --format='%(refname:short)'`
    sha=`git fetch -q && git for-each-ref --count=1 --sort=-refname refs/remotes/origin/z_rb_${relgrp}_[1-9]* --format='%(objectname)'`
    popd 2>&1 > /dev/null

    echo "Branch: $branch_name" 				>> $logfile
    echo "SHA: $sha" 						>> $logfile
    echo "Iteration: $iteration"				>> $logfile
    if [[ $DEBUG -ge 1 ]] ; then 
	echo "DEBUG: Branch: $branch_name"
	echo "DEBUG: SHA: $sha"
	echo "DEBUG: Iteration: $iteration"
    fi

    if [[ $engine -eq 0 ]] ; then
	echo "Engine: not included"				>> $logfile
	if [[ $DEBUG -ge 1 ]] ; then echo "DEBUG: Engine: not included"; fi
    elif [[ $engine -ge 1 ]] ; then
	echo "Engine: included"					>> $logfile
	if [[ $DEBUG -ge 1 ]] ; then echo "DEBUG: Engine: included"; fi
    else
	# no mention of engine
	echo "[no engine]" > /dev/null	# nop
    fi		
    echo ""							>> $logfile

    #
    # Create the announcement email
    #
    echo "From: $email_from"										>  $letter
    echo "To: $email_to"										>> $letter
    if [[ $email_cc != "" ]] ; then
	echo "Cc: $email_cc"										>> $letter
    fi
    if [[ $email_bcc != "" ]] ; then
	echo "Bcc: $email_bcc"										>> $letter
    fi
    echo -n "Subject: "											>> $letter
    if [[ $DEBUG -ge 1 ]] ; then
	echo -n $email_debug_subject 									>> $letter
    fi
    echo -n "Notice: $relgrp - $bldnum"									>> $letter
    if [[ $iteration -gt 0 ]] ; then
	echo -n " iteration $iteration"									>> $letter
    fi
    echo " - Weekly Firmware Release Branch has Been Pulled" 						>> $letter
    echo "MIME-Version: 1.0"										>> $letter
    echo "Content-Type: multipart/related; boundary=\"a1b2c3d4e3f2g1\""					>> $letter
    echo ""												>> $letter
    echo "--a1b2c3d4e3f2g1"										>> $letter
    echo "Content-Type: text/html"									>> $letter
    echo "Content-Transfer-Encoding: 7bit"								>> $letter
    echo ""												>> $letter
    echo "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">"				>> $letter
    echo "<html>"											>> $letter
    echo "<head>"											>> $letter
    echo "<meta http-equiv=\"content-type\" content=\"text/html; charset=ISO-8859.15\">"		>> $letter
    echo "</head>"											>> $letter
    echo "<body>"											>> $letter
    echo "<font face=verdana size=smaller>"								>> $letter
    echo "<font size=-1 color=red><i>" 									>> $letter
    echo "Ignore if not working on limo or bugatti firmware."						>> $letter
    echo "</font></i><br />"										>> $letter
    echo "<br />" 											>> $letter
    echo "Greetings All,<br />"										>> $letter
    echo "<br />" 											>> $letter
    echo "<p>"												>> $letter
    echo "This is a notification email that <u>$relgrp</u> Gold Firmware was branched on"		>> $letter
    echo -n "$timestamp for weekly release $bldnum"							>> $letter
    if [[ $iteration -gt 0 ]] ; then
	echo " iteration $iteration."									>> $letter
    else
	echo "."											>> $letter
    fi
    if [[ $engine -eq 0 ]] ; then
	echo "[Note: This iteration does not include the engine nor finisher.]"				>> $letter
    elif [[ $engine -ge 1 ]] ; then
	echo "[Note: This iteration includes the engine and finisher.]"					>> $letter
    fi
    echo "</p>"												>> $letter
    echo "<b>Branched:</b> <font face=courier size=-1>trunk @ $sha</font><br />"			>> $letter
    echo "<b>Date/time:</b> <font face=courier size=-1>$timestamp</font><br />"				>> $letter
    echo "<b>Branch Name:</b> <font face=courier size=-1>$branch_name</font><br />"			>> $letter
    echo "<br />"											>> $letter
    echo "<p>"												>> $letter
    echo "Use this information to see if your important SHA has made it into the release"		>> $letter
    echo "branch."											>> $letter
    echo "</p>"												>> $letter
    echo "<p>"												>> $letter
    echo "Please <a href=mailto:${email_addsha_to}?subject=${email_addsha_subj}>email us</a>"		>> $letter
    echo "SHAs of any fixes that need to be included but did not make it in."				>> $letter
    echo "Sooner is better &ndash; including more fixes requires a level of requalification"		>> $letter
    echo "of the weekly release and consumes limited resources. Thus, earlier during"			>> $letter
    echo "qualification is better."									>> $letter
    echo "</p>"												>> $letter
    if [[ -e "${ctrldir}/${note}.html" ]] ; then
	#
	# We have a note to include with the email -- we're just going to include it
	# inline as-is, so it needs to be formatted appropriately. (But we'll wrap it
	# in a paragraph just in case.)
	#
	echo "<p>"											>> $letter
	cat ${ctrldir}/${note}.html									>> $letter
	echo "</p>"											>> $letter
    fi
    if [[ -e "${ctrldir}/${note}_${relgrp}.html" ]] ; then
	#
	# We have a release_group specific not, so we'll include that as above.
	#
	echo "<p>"											>> $letter
	cat ${ctrldir}/${note}_${relgrp}.html								>> $letter
	echo "</p>"											>> $letter
    fi 
    if [[ -e "${ctrldir}/${schedule}_${relgrp}.html" ]] ; then 
	#
	# We have a local release-group-specific schedule (html format) to include
	#
	# Note that we are wrapping this block in a div rather than a paragraph
	# as it's likely to be an unordered list), so it must be formatted correctly.
	#
	echo "<br />"											>> $letter
	echo "<div>"											>> $letter
	cat ${ctrldir}/${schedule}_${relgrp}.html							>> $letter
	echo "</div>"											>> $letter
    fi
    if [[ -e "${ctrldir}/${schedule}.html" ]] ; then
	#
	# We have a local release-group-specific schedule (html format) to include
	#
	echo "<br />"											>> $letter
	echo "<div>"											>> $letter
	cat ${ctrldir}/${schedule}.html									>> $letter
	echo "</div>"											>> $letter
    fi
    if [[ -e "${ctrldir}/${schedule}.jpg" ]] ; then
	#
	# If we have an image file, set up a load to it. We'll add the image
	# itself after we close out the body.
	#
	echo "<br />"											>> $letter
	echo "<img src=\"cid:${schedule}\" alt=\"Schedule\">"						>> $letter
	echo "<br />"											>> $letter
    fi

    #
    # Finish the letter
    #
    echo "<br />"											>> $letter
    echo "Thank you,<br />"										>> $letter
    echo "$email_signature<br />"									>> $letter
    echo "<br />"											>> $letter
    echo ""												>> $letter
    echo "</body>"											>> $letter
    echo "</html>"											>> $letter

    #
    # Insert any image file here as inlined base64
    #
    if [[ -e "${ctrldir}/${schedule}.jpg" ]] ; then
	echo "--a1b2c3d4e3f2g1"										>> $letter
	echo "Content-Type: image/jpeg; name=\"${schedule}\""						>> $letter
	echo "Content-ID: <$schedule>"									>> $letter
	echo "Content-Transfer-Encoding: base64"							>> $letter
	echo "Content-Disposition: inline; filename=\"${schedule}.jpg\""				>> $letter
	echo ""												>> $letter
	cat ${ctrldir}/${schedule}.jpg | base64 							>> $letter
	echo ""												>> $letter
    fi

    #
    # Close the email
    #
    echo ""												>> $letter
    echo "--a1b2c3d4e3f2g1"										>> $letter

    #
    # Send the publication email
    #
    if [[ -e "$ctrldir/__branch_email_${relgrp}_disable__" ]] ; then
	echo "DEBUG: __branch_email_${relgrp}_disable__ exists"
    else
	echo "DEBUG: __branch_email_${relgrp}_disable__ does not exist"
    fi
    if [[ -e "$ctrldir/__branch_email_${relgrp}_${dow}_disable__" ]] ; then
	echo "DEBUG: __branch_email_${relgrp}_${dow}_disable__ exists"
    else
	echo "DEBUG: __branch_email_${relgrp}_${dow}_disable__ does not exist"
    fi
    if [[ $force -eq 0 &&
	  ( -e "$ctrldir/__branch_email_${relgrp}_disable__" ||
	    -e "$ctrldir/__branch_email_${relgrp}_${dow}_disable__" ) ]] ; then
	echo "Notification email not sent due to control file disable"			>> $logfile
	echo "(email kept as $CWD/$kept_email)"						>> $logfile
	echo ""										>> $logfile
	# Since we're not sending it, force "-keep" so we can send later if needed
	if [[ $DEBUG -ge 1 ]] ; then
	    echo "DEBUG: Notification email not sent due to control file disable"
	    echo "DEBUG: email kept as $CWD/$kept_email"
	fi
	keep=1
    elif [[ $sendmail -eq 0 ]] ; then
	echo "Notification email not sent due to '-noemail'"				>> $logfile
	if [[ $DEBUG -ge 1 ]] ; then echo "DEBUG: Notification email not sent due to '-noemail'"; fi
	echo "To send later: sendmail -F \"$email_from_name\" -f \"$email_from\" $email_to < $cwd/$letter" >> $logfile
	echo ""										>> $logfile
    else
	sendmail -f "$email_from" -t < $letter						>> $logfile
	echo "Notification email sent: "						>> $logfile
	echo sendmail -F \"$email_from_name\" -f \"$email_from\" $email_to \< $letter	>> $logfile
	if [[ $DEBUG -ge 1 ]] ; then
	    echo "DEBUG: Notification email sent: "
	    echo "DEBUG: sendmail -F \"$email_from_name\" -f \"$email_from\" $email_to < $letter"
	fi
	echo ""										>> $logfile
    fi

    fi	### From: if [[ disabled ]] ; else ###

    #
    # and send the log email to the admins
    #
    echo "Sending log email to $email_admins:"						>> $logfile
    echo sendmail -f \"$email_from\" $email_admins \< $logfile				>> $logfile
    if [[ $DEBUG -ge 1 ]] ; then
	echo "DEBUG: Sending log email to $email_admins:"
	echo "DEBUG: sendmail -f \"$email_from\" $email_admins < $logfile"
    fi
    echo ""										>> $logfile
    sendmail -f "$email_from" $email_admins < $logfile


#
# And we're done.  Clean up and exit
#
    if [[ -e $letter ]] ; then
	if [[ $keep -ge 1 ]] ; then
	    mv -f $letter $logdir/$kept_email
	    if [[ $DEBUG -ge 1 ]] ; then echo "DEBUG: email kept: mv -f $letter $logdir/$kept_email"; fi
	else
	    rm $letter
	fi
    fi
    exit $exitcode

