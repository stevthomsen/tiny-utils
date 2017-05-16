#!/bin/bash

version="1.4"

#set -x		# Echo all lines as expanded/executed
#set -n		# Expand/parse but do not execute

##
## build
##
#
#	Written by:	Joe Eckardt
#	Written:	06 Jun 16
#	Updated: 	
#
#
# Auto-build for Limo and Bugatti "weekly" builds
#


#
# Get our name and path for future use
#
    myname=${0##*/}		# remove any path
    myname=${myname%.*}		# remove any axt

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
email_from="joe.eckardt@hp.com"
email_admins="joe.eckardt@hp.com ktang@hp.com"

#
# Directory pointers
#
git_repo="/work/sirius"					# a git repository to use, will not be modified
logdir="/work/logs"					# directory where logs are written
ctrldir="/work/cronctrl"				# directory for control files
tempdir="/tmp"						# temp directory

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
    OPERATION="build"	# string used in disable control file name

#
# Initialize local variables
#
    DEBUG=0
    exitcode=0		# "successful" exit status as default
    verbose=0		# non-verbose by default
    force=0		# ignore all control files


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
    echo "Usage: ${myname} [-help] [-debug] <release_group> [<iteration>]"
    echo ""
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
		-h*)	
		    #
		    # -help
		    #
		    verbose=1		# force a long usage
		    exitcode=0
		    usage
		    ;;

		-d*)
		    #
		    # -debug
		    #
		    DEBUG=1
#		    email_to=$email_debug_to
		    shift
		    ;;

		-noe*)
		    #
		    # -noemail
		    #
		    sendmail=0
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
		    echo "${myname}:  Unknown switch '$1'"
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
# having processed and removed all of the switches
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
    # Second argument is optional, and is the iteration number
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
    # Get the current date/time for a timestamp
    #
    timestamp=`date +%m/%d/%Y\ @\ %r\ %Z`
    dow=`date +%a | tr '[:upper:]' '[:lower:]'`

    #
    # Set up the log file
    #
    logfile="${logdir}/${myname}_$relgrp.log"

    #
    # Create the header for the logfile
    #
    echo "Subject: Autobuild: build $relgrp $bldnum iteration $iteration $timestamp" > $logfile
    echo ""							>> $logfile
    echo "***** build: $timestamp *****"			>> $logfile
    echo ""							>> $logfile

    echo "myname = $myname" 					>> $logfile
    echo "pwd = `pwd`" 						>> $logfile
    echo "HOME = $HOME" 					>> $logfile


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
	# building disabled
	#
	echo "${myname}: *** Building disabled by control file ***"
	echo ""							>> $logfile
	echo "*** Building disabled by control file ***"	>> $logfile
	echo ""							>> $logfile
    else
	#
	# Building enabled
	#

    ### This else is closed just before the log file is sent ###


    #
    # Compute build number based upon the current week number
    #
    week=`date +%y%W`
    bldnum="$majver.`expr $week + 1`"

    #
    # Perform the actual build
    #
    if [[ $DEBUG -ge 1 ]] ; then
    	echo ""							>> $logfile
	echo "NOT RUN: shr.rb build $relgrp vcd" 		>> $logfile
    	echo ""							>> $logfile
    else
    	echo ""							>> $logfile
	shr.rb build $relgrp vcd 				>> $logfile
    	echo ""							>> $logfile
    fi

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
    echo ""							>> $logfile


    fi	### From: if [[ disabled ]] ; else ###

    #
    # send the log email to the admins
    #
    echo "Sending log email to $email_admins"			>> $logfile
    echo sendmail -f "$email_from" $email_admins \< $logfile	>> $logfile
    echo ""							>> $logfile
    sendmail -f "$email_from" $email_admins < $logfile


#
# And we're done.  Clean up and exit
#
    exit $exitcode

