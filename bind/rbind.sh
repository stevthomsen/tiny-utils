#!/bin/sh

myversion="1.8"

###############################################################################
# Needed by: joe.eckardt@hp.com
# (c) Copyright 2016 HPI
#
# Filename    :	rbind.sh
# Description :	Binds the packages' version which are not in our release group
#             	to fixed versions.
#
# Written by  :	Joe Eckardt
# Date written:	02 May 2016
# Last updated: 23 Aug 2016
#
###############################################################################

#set -x		# Echo all lines as expanded/executed
#set -n		# Expand/parse but do not execute

##
## rbind
##
#
# Bind the packages' version which are not in our release group to fixed versions.
#
# Invocation:
#    rbind [-list] [-force] <product> <release group> <version>
#
#	<product>	One of the known products. This value will be used to
#			specify which set of sed edittings to use.
#
#	<release group>	This argument specifies which subdirectory under sh_proto_release
#			to root the searches in.
#
#	<version>	The full version number, e.g., 002.1625A, to used as the basis of 
#			the binding.
#
# Steps to Use:
# 	1) cd into your sirius_dist working directory. Check out the latest revision of the
#		.yaml files. The results from this script will ultimately replace the .yaml
#		files for your project.
#	2) Run rbind (example):
#		rbind limo limo 002.1625A
#	3) You will be informed which .yaml files were updated; check in the updated .yaml
#		files.
#
# General Description of Operation:
#
#    1)	Some basic sanity checking is done to make sure that we are pointing to 
#	something that appears to be sh_proto_release, and that the specified 
#	release_group exists in this directory, and that the specified version
#	exists within the release_group.
#
#    2) The sh_proto_release/<product_group tree is searched for .yaml files of the
#	specified version. If none found, then we assume the specified product is
#	incorrect and error.
#
#    3)	For each of the discovered .yaml files, we make sure that we have a corresponding
#	one in the current (destination) directory. (This check can be overridden with
#	the -force switch.)
#
#    4) We iterate through the discovered .yaml files, applying the appropriate set of
#	sed edits to each.
#		
# 	The following sed command will be run:
#		sed $sed_all $sed_include $sed_product $file > $file.new
#
# 	Note the order the script fragments are run in, i.e., "all", then "bind_include", and 
#	finally "product-specific".
#
#	Generally, all packages will be bound except for those containing the name of
#	the release group. For example, if binding "limo", then neither "limo_ui" nor
#	"sox_sim_limo" would be bound, but both actually should be. So we use the 
#	"sed_include" sed set to remove these packages from the list of candidate packages
#	to bind.
#       
#
#
# Neccessary Customizations for New Products:
#	1) All of the editting is done using sed commands. See the "configurable parameters"
#	section immediately below. The following product-specific variables must be defined:
#		<product>_basedir
#		<product>_relgrp
#		<product>_sed_include
#		<product>_sed
#
#	See the sed man pages for specifics on how to structure the commands on the sed 
#	lines. You will need these two definitions for each new product.
#
#	Please use the existing "limo" or "bugatti" sections as examples.
#
#	2) Also in the configuration section, the new product needs to be appended to the 
#	lists:
#		products+=("<new product>")
#		relgroups+=("<new release group>")
#
#	3) Search for the string: "# Additional products should be added here". Add a case
#	clause for each new product that references the three product-specific variables 
# 	created in step 1 above and assigns them to the associated global variables.
#		basedir
#		sed_product
#		sed_include
#


##########
##########
##
## Configurable parameters
##

    #
    # These two definitions are used to build a list of supported values
    #
    # Each product definition should include two lines of the form:
    #	products+=("<product>")
    #	relgroups+=("<relgrp>")
    #
    products=()		# Dynamically created list of suported products
    relgroups=()	# Dynamically created list of supported release groups


    ########################################
    # Platform-independent ("all") changes #
    ########################################

    #
    # The following will be done for all products
    #
    # Generally there should not be any need to change or modify this section.
    #
    sed_all="					\
	    -e s/ram_[sn]*arel/%r/ 		\
	    -e s/[sn]*arel/%t/ 			\
	    -e /^opkg_manage_deps/d"


    #####################
    # Platform Specific #
    #####################

    #
    # $<product>_basedir
    #     The basedir is the path to the sh_proto_release directory that contains
    #     this release group. This will be the source for all of the binding 
    #     information by this program.
    #
    #
    # $<product>_sed_include
    # $<product>_sed
    #     Each platform must have its own sed_<platform> and sed_<platform>_include
    #     defined.
    #
    #     Each substitution command will be applied to each line of the .yaml file, 
    #     which is to say, the changes are global -- be careful of the order that
    #     you enter them in so you don't clobber something inadvertantly.
    #
    #     Exclusions are generally lines that include the product name that would
    #     normally be changed by the global commands, but are really special cases
    #     that are not in our release group
    #     Each exclusion pattern match line ends with "b", which is the "branch"
    #     directive which effectively skips all following edittings for the
    #     current line.
    #
    # $products()
    # $relgroups()
    #     Additionally, each new product must add its product name(s) and its
    #     associated release group to $products() and $relgroups().
    #


    ##
    ## Limo
    ##
    #
    products+=("limo")		# add to list of supported products

    # limo base directory
    limo_basedir="/sirius/cr/vcd/sh_proto_release"

    # limo release group name
    limo_relgrp="limo"
    relgroups+=($limo_relgrp)	# add to list of supported release groups

    # limo specific include(also used for bugatti)
    limo_sed_include="				\
	    -e /limo_ui/b			\
	    -e /limo8_cp_ui/b			\
	    -e /limo8_ui_conf/b			\
	    -e /limo4.3_ui_conf/b		\
	    -e /pe_sim_limo/b			\
	    -e /sox_sim_limo/b			\
	    -e /limo_pq_reports/b		\
	    -e /limo_animations/b		\
	    -e /limo8_animations/b		\
	    -e /limo_mfp_animations/b		\
	    -e /limo_sfp_animations/b		\
	    -e /limo_images/b			\
	    "

    # limo specific edits
    limo_sed="					\
	    -e s/\\(limo.*\\)=.*$/\1/		\
	    "

    ##
    ## Bugatti
    ##
    #
    products+=("bugatti")
    bugatti_relgrp="bugatti_3_0"
    relgroups+=($bugatti_relgrp)
    bugatti_basedir="/sirius/cr/vcd/sh_proto_release"
    bugatti_sed_include=$limo_sed_include 		# bugatti includes - uses limo_sed_include
    bugatti_sed="				\
	    -e s/\\(limo.*\\)=.*$/\1/		\
	    -e s/\\(bugatti.*\\)=.*$/\1/	\
	    "

    ##
    ## Triptane/Limtane
    ##
    #
    products+=("triptanelimtane" "triptane" "limtane")
    triptanelimtane_relgrp="triptane_limtane_3_0"
    relgroups+=($triptanelimtane_relgrp)
    triptanelimtane_basedir="/sirius/cr/vcd/sh_proto_release"
    triptanelimtane_sed_include=""
    triptanelimtane_sed="			\
	    -e s/\(maverick.*\)=.*$/\1/		\
	    -e s/\(iceman.*\)=.*$/\1/ 		\
	    -e s/\(triptane.*\)=.*$/\1/ 	\
	    -e s/\(limtane.*\)=.*$/\1/		\
	    "

    ##
    ## Palermo
    ##
    #
    # http://sgpfwws.ijp.sgp.rd.hpicorp.net/cr/bpd/sh_release/palermo_3_0/
    #
    # Unless augmented, any line containing "palermo*=<version>" has the "=<version>" removed
    #
    products+=("palermo")
    palermo_relgrp="palermo_3_0"
    relgroups+=($palermo_relgrp)
    palermo_basedir="/sirius/cr/bpd/sh_proto_release"
    palermo_sed_include=""
    palermo_sed="				\
	    -e s/\(palermo.*\)=.*$/\1/		\
	    "

    ##
    ## Verona
    ##
    #
    # http://sgpfwws.ijp.sgp.rd.hpicorp.net/cr/bpd/sh_release/verona_sgp/
    #
    # Unless augmented, any line containing "verona.*=<version>" has the "=<version>" removed
    #
    products+=("verona")
    verona_relgrp="verona_sgp"
    relgroups+=($verona_relgrp)
    verona_basedir="/sirius/cr/bpd/sh_proto_release"
    verona_sed_include=""
    verona_sed="				\
	    -e s/\(verona.*\)=.*$/\1/		\
	    "

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
    keep=0		# keep .bak files, def=nokeep
    force=0		# force binding process even if not in sirius_dist, def=noforce
    exitcode=0		# "successful" exit status as default
    verbose=0;		# non-verbose by default
    list=0
    prod=""
    relgrp=""
    vers=""
    destdir=`pwd`
    srcdir=""
    sed_include=""
    sed_product=""

#
# Join function
#
function join { local IFS="$1"; shift; echo "$*"; }


#
# Usage message
#
function usage
{
    if [[ $verbose -ge 1 ]] ; then
	echo "v$myversion"
    fi
    echo ""
    echo "Usage: ${myname} [-list] [-force] <product> <release group> <version>"
    echo ""
    if [[ $verbose -ge 1 ]] ; then
	echo "    <product>       Product name, one of <`join \| ${products[*]}`>"
	echo "    <release group> Release group to process, one of <`join \| ${relgroups[*]}`>"
	echo "    <version>       Full version number, e.g., \"002.1615A\""
	echo ""
	echo "Important! -- you must be in your sirius_dist directory when invoking this utility"
	echo ""
	echo "Optional switches:"
	echo "    -help           Display this usage message and exit"
	echo "    -[no]force      Force binding to continue regardless of current directory (def=noforce)"
	echo "    -list           Display a list of the current revisions that start with <version>"
	echo "                    that are available in the specified release group."
	echo "    -[no]keep       Keep .bak copies of the original files (def=nokeep)"
	echo "    -version        Display this program's version number and exit"
	echo ""
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

		-v*)
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
		    shift;
		    ;;

		-l*)
		    #
		    # -list
		    #
		    # List all of the known version numbers for this release group
		    #
		    list=1
		    shift
		    ;;

		-f*)
		    #
		    # -force
		    #
		    # Force binding to continue even if it appears we are not in a
		    # sirius_dist directory
		    #
		    force=1
		    shift
		    ;;

		-nof*)
		    #
		    # -noforce
		    #
		    # Do not allow binding to continue if it appears we are not in a
		    # sirius_dist directory
		    #
		    force=0
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
	exitcode=2
	usage
    fi


#
# Process command line args
#
# Note that no checking is done here, so it MUST be typed in correctly
# by the user
#

    #
    # First argument must be product
    #
    # The products that we support are hard-coded here (which isn't
    # optimal but is unavoidable)
    #
    prod=$1
    case $prod in
	limo)
	    #
	    # Limo
	    #
	    basedir=$limo_basedir
	    sed_product=$limo_sed
	    sed_include=$limo_sed_include
	    ;;

	bugatti)
	    #
	    # Bugatti
	    #
	    basedir=$bugatti_basedir
	    sed_product=$bugatti_sed
	    sed_include=$bugatti_sed_include
	    ;;

	triptane|limtane|triptane_limtane)
	    #
	    # Triptane/Limtane
	    #
	    basedir=$triptanelimtane_relgrp
	    sed_product=$triptanelimtane_sed
	    sed_include=$triptanelimtane_sed_include
	    ;;

	palermo)
	    #
	    # Palermo
	    #
	    basedir=$palermo_relgrp
	    sed_product=$palermo_sed
	    sed_include=$palermo_sed_include
	    ;;

	verona)
	    #
	    # Verona
	    #
	    basedir=$verona_relgrp
	    sed_product=$verona_sed
	    sed_include=$verona_sed_include
	    ;;

	#
	# Additional products should be added here
	#

	*)
	    #
	    # Unknown product
	    #
	    echo "${myname}: Unknown product '$1'"
	    exitcode=6
	    usage
	    ;;
    esac

    #
    # Second argument must be the release group. We'll validity check
    # it later in the code
    #
    relgrp=$2
    srcdir="$basedir/$relgrp"

    #
    # And finally the third argument must be the version. Also will validity
    # check this later.
    #
    vers=$3

    #
    # Print out our working variable
    #
    if [[ $DEBUG -ge 1 ]] ; then
	echo "prod = '$prod'"
	echo "release group = '$relgrp'"
	echo "vers = '$vers'"
	echo "basedir = '$basedir'"
	echo "srcdir = '$srcdir'"
	echo "destdir = '$destdir'"
    fi

#
# Some minor sanity checking of the users' inputs.  We'll try to check
# for the existence of some paths that should exist if something rational
# was entered.  But no guarantees at this point.
#
    #
    # Check that there is a directory of $relgrp in sh_proto_release
    #
    if [[ ! -e "$srcdir" ]] ; then
	echo "${myname}: Unknown release group '$relgrp'"
	exitcode=4
	usage
    fi

    #
    # If we were asked to list the version, do so now and exit
    #
    if [[ $list -ge 1 ]] ; then
	files=(`find $srcdir -maxdepth 6 -type f \( -name "*${vers}*_assert.yaml" \) -print | sed -e "s/_assert.*$//" -e "s/.*_//" | sort -u`)
	if [[ ${#files[@]} -eq 0 ]] ; then
	    echo "${myname}: Unknown release number '$vers'"
	else
	    echo ""
	    echo "${#files[@]} versions found for '$relgrp':"
	    for file in "${files[@]}" ; do
		echo "    $(basename $file)"
	    done
	    echo ""
	fi
	exit 0
    fi

    #
    # Make sure the version includes the major version
    #
    if [[ $vers != *\.* ]] ; then
	echo "${myname}: Invalid version number given (missing major version), '$vers'"
	exitcode=4
	usage
    fi

    
    #
    # Now try to check the given version number
    #
    files=(`find $srcdir -maxdepth 6 -type f \( -name "*${vers}*_assert.yaml" \) -print 2>/dev/null`)
    if [[ ${#files[@]} -eq 0 ]] ; then
	echo "${myname}: Unknown release number '$vers'"
	exitcode=4
	usage
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
    # Determine which .yaml files we need to copy to sirius_dev as
    # templates
    #
    if [[ ! -e $srcdir ]] ; then
	echo "${myname}: Input directory '$srcdir' does not exist"
	exit 3
    fi
    cd $srcdir
    files=(`find -maxdepth 6 -type f \( -name "*${vers}*_assert.yaml" \) -print`)

    #
    # Did we find any matching files?  If not, then the given product 
    # must be bad.
    #
    if [[ ${#files[@]} -eq 0 ]] ; then
	echo "${myname}: No files found matching the given paramters"
	exitcode=4
	usage
    fi

    #
    # We are going to pre-check that all the files that we WILL create
    # already exist in the current directory. This will give us some
    # confidence that the use has cd'ed to sirius_dist before running.
    # If not, we're going to bail (unless we get a -f switch).
    #
    # In point of fact, we don't NEED to be in sirius_dist, but that's
    # where the results are intended to go, so we're trying to be helpful
    # here.
    #
    issue=0	# assume ok unless we find a problem
    for file in "${files[@]}" ; do
	file=$(basename $(dirname $(dirname $(dirname "$file")))).yaml
	if [[ ! -f "$destdir/$file" ]] ; then
	    if [[ $issue -eq 0 ]] ; then
		#
		# Only print the error "header" if this is the first
		# missing file to list
		#
		echo ""
		if [[ $force -eq 0 ]] ; then
		    echo "${myname}: ERROR: The current directory '$destdir' does not appear to be sirius_dist"
		else
		    echo "${myname}: NOTE: The current directory '$destdir' does not appear to be sirius_dist, but due to -force we will proceed anyway"
		fi
		echo ""
		echo "    The following expected files are missing:"
		issue=1
	    fi
	    echo "        $file"
	fi
    done
    echo ""
    if [[ $issue -ge 1 && $force -eq 0 ]] ; then
	#
	# Found missing files and no -force, so this
	# is an error
	#
	echo "Please 'cd' to your sirius_dist and 'git checkout' to the desired revision"
	echo "before invoking this utility."
	echo ""
	echo "Note: If you wish to create the output files in the current directory"
	echo "      despite the missing expected files, use the -force switch."
	echo ""
	exit 5
    fi

    #
    # Iterate through the files that we found, copying each candidate to the
    # sirius_dist directory
    #
    echo "copying ${#files[@]} files from $srcdir..."
    echo ""
    for file in "${files[@]}" ; do
	echo "copying $(basename $file)..."
	if [[ -e $destdir/$(basename $(dirname $(dirname $(dirname "$file")))).yaml ]] ; then
	    cp $destdir/$(basename $(dirname $(dirname $(dirname "$file")))).yaml $destdir/$(basename $(dirname $(dirname $(dirname "$file")))).yaml.bak
	fi
	cp $file $destdir/$(basename $(dirname $(dirname $(dirname "$file")))).yaml
    done
    echo ""

    #
    # Process each of the new .yaml files to unbind the packages that WE release
    #
    # But not:
    # 	Limo: rebind limo_ui, limo8_cp_ui, limo4.3_ui_conf, limo8_ui_conf, pe_sim_limo, sox_sim_limo.
    #
    cd $destdir
    for file in "${files[@]}" ; do
	file=$(basename $(dirname $(dirname $(dirname "$file")))).yaml
	echo "updating $file..."
	#
	# In the following, the matches ended in "/b" will stop processing
	# the current line if matched.
	#
	sed $sed_all $sed_include $sed_product $file > $file.new
	mv $file.new $file
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
    # and exit
    #
    exit $exitcode

