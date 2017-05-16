#!/bin/sh

myversion="1.2"

###############################################################################
# Needed by: joe.eckardt@hp.com
# (c) Copyright 2016 HPI
#
# Filename    :	take.sh
# Description :	Update product's yaml for a given package with a newer (or at
#		least different) version number.
#
# Written by  :	Joe Eckardt
# Date written:	23 Jun 2016
# Last updated: 
#
###############################################################################

#set -x		# Echo all lines as expanded/executed
#set -n		# Expand/parse but do not execute

##
## take.sh
##
#
# Update a package's version (i.e., "take the new version") for all .yaml files
# matching the specified product name.
#
# Invocation:
#    take <product> <package> <version>
#
#	<product>	One of the known products. This is used to determine which
#			.yaml files to edit using a simple glob.
#
#	<package>	The package whose version to update in the .yaml files
#
#	<version>	The full version number, e.g., 001.1625A, to substituted in
#			the matching files.
#
# Steps to Use:
#	TBD
#
# General Description of Operation:
#	TBD
#
# Neccessary Customizations for New Products:
#	TBD
#


##########
##########
##
## Configurable parameters
##


##
##
########### End of Configurable Parameters ###########
######################################################


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


#
# Some local constants and pointers
#
    MINARGS=3		# minumum number of required args, excluding switches
    MAXARGS=3		# maximum number of args allowed, excluding switches (-1=no max)


#
# Initialize local variables
#
    DEBUG=0		# enable debug mode
    keep=1		# keep .bak files, def=keep
    exitcode=0		# "successful" exit status as default
    verbose=0;		# non-verbose by default
    modified=0



#####################
# Support Functions #
#####################

#
# Usage message
#
function usage
{
    if [[ $verbose -ge 1 ]] ; then
	echo "v$myversion"
    fi
    echo ""
    echo "Usage: ${myname} <product> <package> <version>"
    echo ""
    if [[ $verbose -ge 1 ]] ; then
	echo "    <product>       Product name, e.g., \"limo\""
	echo "    <package>       Package whose version to update in the .yaml files"
	echo "    <version>       Full version number, e.g., \"001.1615A\""
	echo ""
	echo "Important! -- you must be in your sirius_dist directory when invoking this utility"
	echo ""
	echo "Optional switches:"
	echo "    -help           Display this usage message and exit"
	echo "    -[no]keep       Keep .bak copies of the original files (def=nokeep)"
	echo "    -version        Display this program's version number and exit"
	echo ""
    fi
    exit $exitcode
}


#
# Join function
#
# Note: push: var+=("new")
#
function join { local IFS="$1"; shift; echo "$*"; }

#
#####



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

		-ver*)
		    #
		    # -version
		    #
		    # Display the version number
		    #
		    echo "v$myversion"
		    exit 0
		    ;;

		-debug)
		    #
		    # -debug
		    #
		    DEBUG=1		# enable debug mode
		    shift
		    ;;

		-v*)
		    #
		    # -verbose
		    #
		    # Provide vebose output
		    #
		    verbose=1
		    shift
		    ;;

		-k*)
		    #
		    # -keep
		    #
		    # Keep backup copies of the original files
		    #
		    keep=1
		    shift
		    ;;

		-nok*)
		    #
		    # -nokeep
		    #
		    # Remove backup copies of the original files
		    #
		    keep=0
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
# having processed and removed all of the switches
#
    if [[ $# -lt $MINARGS || ( $MAXARGS -ge 0 && $# -gt $MAXARGS ) ]] ; then
	echo ""
	echo "${myname}: Missing required argument"
	echo ""
	exitcode=2
	verbose=0
	usage
    fi

#
# Process command line args
#
# AT this point we're just going to grab them from the command line. We'll
# do some sanity checking on them later.
#
    #
    # First argument is the product name
    #
    product=$1

    #
    # Second arg is the package to update
    #
    package=$2

    #
    # Third arg is the new version number
    #
    version=$3
    if [[ ! $version =~ ^00[0-9]\.[0-9][0-9][0-9][0-9][A-Z]$ ]] ; then
	echo "${myname}: Invalid version number '$version' (must be a full version number)"
	exit 3
    fi



##################
#
# The real work...
#

    #
    # Save our original directory so that we can get back if necessary
    #
    origdir=`pwd`

    #
    # Make sure we the given "product" matches at least one .yaml file
    # in the current directory
    #
    if [[ `ls -1 $product*.yaml 2> /dev/null | wc -l` -eq 0 ]] ; then
	echo "${myname}: ERROR: No matching .yaml files in the current directory"
	exit 2
    fi

    #
    # Get the list of candidate files that contain the package that we're
    # changing
    #
    filect=`grep -l $package $product*.yaml | grep -v last_good.yaml | wc -l`
    if [[ `grep -l $package $product*.yaml | grep -v last_good.yaml | wc -l` -eq 0 ]] ; then
	echo "${myname}: No matching package '$package' found in '$product*' .yaml files in the current directory"
	exit 3
    fi
    files=`grep -l $package $product*.yaml | grep -v last_good.yaml`

    #
    # We found some files with matches, so iterate through each doing the changes
    #
    for file in ${files[@]} ; do
	#
	# List the files as we change them
	#
	echo "$file..."

	#
	# Remove any old .bak file
	#
	if [[ -e $file.bak ]] ; then
	    rm $file.bak
	fi

	#
	# Change the file
	#
	# We have two distinct cases that must be handled:
	#  1) The package has been previously bound so there is an existing rev number that must be replaced
	#  2) The package has not been previously bound, so we have to add the "=$version" at the end
	#
	# At present only case #1 is being handled
	#
	#sed -e "/ $package/s/\\(=.*00[0-9]\\.\\)[0-9][0-9][0-9][0-9][A-Z]$/\\1$version/" $file > $file.new
	#
	# The following version should handle both cases, at the expense of having to specify the full version
	#
	sed -e "/ $package/s/=.*$/=$version/" -e "/ $package.*=/b" -e "/ $package/s/$/=$version/" $file > $file.new

	#
	# Did we change anything?
	#
	`diff $file $file.new 2>&1 > /dev/null`
	stat=$?
	if [[ $stat -eq 1 ]] ; then
	    ((changed+=1))
	    if [[ $verbose -ge 1 ]] ; then
		diff $file $file.new
	    fi
	    if [[ $DEBUG -eq 0 ]] ; then
		mv $file $file.bak
		mv $file.new $file
	    fi
	fi
    done


#
# And we're done.  Clean up and exit
#
    #
    # Remove any .bak files unless requested to keep
    #
    if [[ `ls -1 *.bak 2> /dev/null | wc -l` -gt 0 && $keep -eq 0 ]] ; then
	rm *.bak 2> /dev/null
    fi

    #
    # Remove any stray .new files, probably left over from previous
    # aborted runs
    #
    if [[ `ls -1 *.new 2> /dev/null | wc -l` -gt 0 ]] ; then
	rm *.new 2> /dev/null
    fi

    #
    # Print a summary
    #
    if [[ $changed -gt 0 ]] ; then
	echo ""
	echo "$changed files updated"
	echo ""
    else
	echo ""
	echo "no files updated"
	echo ""
    fi

    #
    # and exit
    #
    exit $exitcode

