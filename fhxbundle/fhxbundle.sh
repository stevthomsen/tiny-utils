#!/bin/sh

version="1.20"

#set -x     # Echo all lines as expanded/executed
#set -n     # Expand/parse but do not execute

##
## fhxbundle.sh
##
#
# Very basic script to bundle specified engine and cp hex files into a single
# hfx file for loading.
#
# IMPORTANT NOTE: Only modest error checking is done in this version, so it's possible
# to get an error buried in the output stream that the program doesn't catch and 
# handle. It is intended to eventually re-implement this as a full python script with 
# robust checking to give more reliability.
#
# This version is focused on combining engine and cp images. In the future, other
# bundlings will also be supported.
#
# Sample typical invocation:
#   fhxbundle -v -keep -release -target assert 1615K
#   fhxbundle -v -keep -proto -arel 002.1615K
#   fhxbundle -v -keep -proto -target narel -phase lp3 002.1615K 002.1615E
#   fhxbundle -v -keep -proto -target narel -phase lp3 <host (limo/limo8/limo_mfp)> < host distro version> <guest (limo_cp) distro version>
#
#   In the above example, omit -release to default to -proto;
#   use -target assert or -target nonassert or -target narel as
#       appropriate (or their aliases -arel | -narel)
#


#
# Get our name and path for future use
#
    myname=${0##*/}         # remove any path
    myname=${myname%.*}     # remove any ext

    if [[ $0 = */* ]] ; then
        mypath=${0%/*}      # remove prog name leaving path
    else
        mypath="."          # no path at all, assume cwd
    fi


#
# Some local constants and pointer
#
    MINARGS=3               # minumum number of required args, excluding switches
    MAXARGS=3               # maximum number of args allowed, excluding switches (-1=no max)

#
# Configuration variables
#
    release_dir_name="sh_release"      # subdir name for "release"
    proto_dir_name="sh_proto_release"  # subdir name for "proto"
    dbfs_name="dbfs"                   # name to use for dbfs subdir
    ref_files_name="ref_files"         # name to use for ref_files subdir
    boot_name="boot"                   # name to use for boot subdir
    basedir="/tmp"                     # base directory to use, overridable from command line, def=/tmp
    destdir=`pwd`                      # directory where to put the resulting image, def=cwd

#
# Initialize local variables
#
    DEBUG=0                            # -debug switch will set this to "non-null"
    exitcode=0                         # "successful" exit status as default
    verbose=0                          # non-verbose by default
    host_type=""                       # either limo_mfp or limo8
    guest_type="limo_cp"
    host_major_version="002"           # major version, def=002; this may get overriden by host_version
    cp_major_version="002"             # major version, def=002; this may get overriden by cp_verion
    host_version=""                    # engine minor version to use, default "unknown"
    cp_version=""                      # cp minor version to use, default "unknown"
    keep=0                             # 1=do not delete intermediate files before exit
    release_name=$proto_dir_name       # release type to use, def=proto
    hwphase="lp3"                      # hardware version, def=lp3
    target="assert"                    # target, def=assert
    workdir="${basedir}/${myname}_$$"  # temporary work directory
    releasedir=""                      # release directory [computed]
    release_group="limo"
    sh_base_url="http://rndapp1.vcd.hp.com/sirius/cr/vcd/"
    include_datafs=0
    include_recoveryfs=0

#
# Usage message
#
function usage
{
    if [[ ${verbose} -ge 2 ]] ; then
        echo "v$version"
    fi
    echo ""
    echo "Usage: ${myname} [-verbose] [-keep] [-relgroup {limo|..}] [-published {yes|no}] [-target {assert|nonassert|signable_assert}] [-hwphase {lp2|lp3|..}] [-workdir <workdir>] [-out <destdir>] [-autocopy] [-datafs] <host_type {limo|limo8|limo_mfp}> <host_version> <cp_version>"
    echo ""
    if [[ ${verbose} -ge 3 ]] ; then
        echo "  Required Arguments:"
        echo "    <host_type>          Choose type of host distribution to use: { limo8 | limo_mfp }"
        echo "    <host_version>       Host distribution revision"
        echo "    <cp_version>         Limo_cp distribution revision."
        echo ""
        echo "  Optional Arguments:"
        echo "    -help                Print usage message"
        echo "    --help               Print this extended usage message"
        echo "    -verbose             Extended output"
        echo "    -keep                Do not delete intermediate files from working directory upon exit"
        echo "    -relgroup <name>     Sirius Hub release group name. ( default=limo )"
        echo "    -published <yes|no>  Use published distributions; sh_release; or unpublished distributions; sh_proto_release. { yes | no }. ( default=no )"
        echo "    -target <val>        Use target { assert | arel }, { nonassert | narel }, or { signable_assert | sarel }. ( default=assert )"
        echo "    -hwphase <hwphase>   Hardware phase of firmware. ie: lp2, lp3, mp1, etc"
        echo "    -workdir <workdir>   Working directory to build the image in, def=/tmp"
        echo "    -out <destdir>       Destination output directory."
        echo "    -[auto]copy          Copy the resulting combined image to the appropriate release directory"
        echo "    -datafs              Include the datafs partition - Limo only."
#        echo "    -recovery            Include the recovery partition."
        echo ""
        echo "Note: switches may be abbreviated"
        echo ""
        echo "Important note: You must have sudo privs to successfully run this utility, and"
        echo "you may be prompted to enter your sudo password."
        echo""
    fi
    exit ${exitcode}
}

#
# Pause Function
#
function pause()
{
    read -p "$*"
}

msgv(){
    local lvl=$1
    local m="$2"
    if [[ ${verbose} -ge $lvl ]] ; then
        msg "${m}"
    fi
}

msg(){
    local m="$1"
    ( { set +x; } 2>/dev/null; echo -e "${m}" )
}

download(){
    local src="$1"
    local dest="$2"

    msgv 1 "++ curl --fail -0 ${src} > ${dest}"
    curl --fail -0 "${src}" > "${dest}"
    stat=$?
    if [[ $stat -gt 0 ]] ; then
        msg "${myname}: ERROR: Unable to access '${src}'"
        exit 5
    fi
}

################
# Main Program #
################

#
# Process command line switches
#
    if [[ $# -gt 0 ]] ; then
        while [[ ${1} = -* ]] ; do
            case ${1} in
                -debug)
                    #
                    # -debug
                    #
                    DEBUG=1
                    verbose=5
                    shift
                    ;;

                -vers*)
                    #
                    # -version
                    #
                    # Print the version number and exit
                    #
                    echo "${myname} v${version}"
                    exit 0
                    ;;

                -k*)
                    #
                    # -keep - do not delete the intermediate files
                    #
                    keep=1
                    shift
                    ;;

                -au* | -c*)
                    #
                    # -autocopy | -copy
                    #
                    # Copy resulting bundled file to the appropriate target directory
                    #
                    copy=1
                    shift
                    ;;

                -hwph* | -ph*)
                    #
                    # -hwphase {lp2|lp3|..}
                    #
                    shift
                    if [[ ${1} == "" ]] ; then
                        echo "${myname}: Missing required argument for -hwphase"
                        exitcode=3
                        usage
                    fi
                    hwphase="${1}"
                    shift
                    ;;

                -r*)
                    #
                    # -relgroup {limo|blah}
                    #
                    shift
                    if [[ ${1} == "" ]] ; then
                        echo "${myname}: Missing required argument for -relgroup"
                        exitcode=3
                        usage
                    fi
                    release_group="${1}"
                    shift
                    ;;

                -t*)
                    #
                    # -target {assert|arel|nonassert|narel|signable_assert|sarel}
                    #
                    # The argument pattern is loose enough to accept any of
                    # assert | arel | nonassert | narel
                    #
                    shift
                    if [[ ${1} == "" ]] ; then
                        echo "${myname}: Missing required argument for -target"
                        exitcode=3
                        usage
                    else
                        case ${1} in
                            arel | assert)
                                target="assert"
                                shift
                                ;;
                            narel | nonassert)
                                target="nonassert"
                                shift
                                ;;
                            sarel | signable_assert)
                                target="signable_assert"
                                shift
                                ;;
                            *)
                                #
                                # Unrecognized phase
                                #
                                echo "${myname}: Unknown target '${1}' for -target switch"
                                exitcode=3
                                usage
                                ;;
                        esac
                    fi
                    ;;

                -pu*)
                    #
                    # -published {yes|no}
                    #
                    shift
                    if [[ ${1} == "" ]] ; then
                        echo "${myname}: Missing required argument for -published"
                        exitcode=3
                        usage
                    else
                        case ${1} in
                            y | yes)
                                release_name=${release_dir_name}
                                shift
                                ;;
                            n | no)
                                release_name=${proto_dir_name}
                                shift
                                ;;
                            *)
                                #
                                # Unrecognized phase
                                #
                                echo "${myname}: Unknown argument '$1' for -published switch. Please use 'yes' or 'no'."
                                exitcode=3
                                usage
                                ;;
                        esac
                    fi
                    ;;

                -w*)
                    #
                    # -workdir - working directory to build in
                    #
                    # This parameter overrrides the default of /tmp. Specified directory
                    # must already exist, and will not be removed during cleanup. A subdir
                    # based upon $$ will be created under this location, and that subdir
                    # WILL be removed during cleanup.
                    #
                    shift
                    if [[ ${1} == "" ]] ; then
                        # Missing argument
                        echo "${myname}: Missing parameter for -workdir switch"
                        exitcode=1
                        usage
                    fi

                    if [[ ! -d ${1} ]] ; then
                    # directory doesn't exist
                        echo "${myname}: Specified directory '${1}' doesn't exist"
                        exitcode=1
                        usage
                    fi

                    if [[ ${1} == "." ]] ; then
                        basedir=`pwd`
                    else
                        basedir=${1}
                    fi
                    workdir="${basedir}/${myname}_$$"
                    shift
                    ;;

                -o*)
                    #
                    # -out <destdir> - output directory
                    #
                    shift
                    if [[ ${1} == "" ]] ; then
                        # Missing argument
                        echo "${myname}: Missing parameter for -out switch"
                        exitcode=1
                        usage
                    fi

                    if [[ ! -d ${1} ]] ; then
                    # directory doesn't exist
                        echo "${myname}: Specified directory '${1}' doesn't exist"
                        exitcode=1
                        usage
                    fi

                    if [[ ${1} == "." ]] ; then
                        msgv 1 "SETTING OUT TO PWD"
                        destdir=`pwd`
                    else
                        msgv 1 "SETTING OUT TO ${1}"
                        destdir=${1}
                    fi
                    shift
                    ;;

                -h*)
                    #
                    # -help
                    #
                    verbose=2       # force a long usage
                    exitcode=0
                    usage
                    ;;

                --h*)
                    #
                    # --help
                    #
                    verbose=3       # force a extended usage
                    exitcode=0
                    usage
                    ;;

                -v*)
                    #
                    # -verbose
                    #
                    verbose=1
                    shift
                    ;;

                --v*)
                    #
                    # --verbose
                    #
                    verbose=2
                    shift
                    ;;
                -datafs)
                    include_datafs=1
                    shift
                    ;;
                -recovery)
                    include_recoveryfs=1
                    shift
                    ;;
                *)
                    #
                    # Unrecognized switch
                    #
                    echo "${myname}:  Unknown switch '${1}'"
                    echo ""
                    exitcode=1      # exitcode 1: Invocation error: unknown switch or illegal command line argument
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
    if [[ $# -lt ${MINARGS} || ( ${MAXARGS} -ge 0 && $# -gt ${MAXARGS} ) ]] ; then
        echo "Incorrect required arguments."
        exitcode=2
        usage
    fi


#
# Process command line args
#
    #
    # host type - currently only limo8 and limo_mfp are supported.
    #
    host_type=${1}
    shift
    case ${host_type} in
        limo)
            ;;
        limo8 | 8)
            ;;
        limo_mfp | mfp)
            ;;
        *)
            #
            # Unrecognized host_type
            #
            echo "${myname}: Unknown host_type '${host_type}'. Currently only host_types of {limo|limo8|limo_mfp} are supported."
            exitcode=3
            usage
            ;;
    esac

    #
    # host version
    #
    # either 000.0000A or 0000A
    #
    host_version=${1}
    shift
    if [[ ${host_version} != [0-9]* ]] ; then
	#
	# Starts with a non-numeric, which can't be right
	#
	echo "${myname}: ERROR: Specified host version '${host_version}' is not a valid version string."
	echo "            (It should be of the form either '000.0000A' or '0000A'.)"
	exitcode=3
	exit $exitcode
    fi
    if [[ ${host_version} == *.* ]] ; then
        #
        # Embedded '.' so must be a full version, so break it into pieces
        #
        host_major_version=${host_version/.*/}
        host_version=${host_version/*./}
    fi

    #
    # cp version
    #
    # either 000.0000A or 0000A
    #
    cp_version=${1}
    shift
    if [[ ${cp_version} != [0-9]* ]] ; then
	#
	# Starts with a non-numeric, which can't be right
	#
	echo "${myname}: ERROR: Specified cp version '${cp_version}' is not a valid version string"
	echo "            (It should be of the form either '000.0000A' or '0000A'.)"
	exitcode=3
	exit $exitcode
    fi
    if [[ ${cp_version} == *.* ]] ; then
        #
        # Embedded '.' so must be a full version
        #
        cp_major_version=${cp_version/.*/}
        cp_version=${cp_version/*./}
    fi

    #
    # Set up our paths
    #
    dbfs="${workdir}/${dbfs_name}"
    ref="${workdir}/${ref_files_name}"
    boot="${workdir}/${boot_name}"
    releasedir="/sirius/cr/vcd/${release_name}/${release_group}/${host_type}_dist_${hwphase}/${host_major_version}.${host_version}/${target}"


#
# Display a summary of the parameters that we are using
#
    if [[ ${verbose} -ge 1 || ${DEBUG} -ge 1 ]] ; then
        echo ""
        echo "Using:"

        echo -n "  basedir = '${basedir}'"
        if [[ ${basedir} == `pwd` ]] ; then
            echo " (current directory)"
        else
            echo ""
        fi

        echo -n "  workdir = '${workdir}'"
        if [[ ${workdir} == `pwd` ]] ; then
            echo " (current directory)"
        else
            echo ""
        fi

        echo -n "  destdir = '${destdir}'"
        if [[ ${destdir} == `pwd` ]] ; then
            echo " (current directory)"
        else
            echo ""
        fi
        echo ""

        echo "  host_type    = '${host_type}'"
        echo "  host_version = '${host_major_version}.${host_version}'"
        echo "  cp_version   = '${cp_major_version}.${cp_version}'"
        echo "  hwphase      = '${hwphase}'"
        echo "  release_type = '${release_name}'"
        echo "  target       = '${target}'"
        echo "  releasedir   = '${releasedir}'"
        echo ""
        if [[ $(( ${include_datafs} + ${include_recoveryfs} )) -gt 0 ]]; then
            echo "  additional partitions:"
            if [[ ${include_datafs} -gt 0 ]];then echo "    datafs"; fi
            if [[ ${include_recoveryfs} -gt 0 ]]; then echo "    recovery"; fi
            echo ""
        fi
        echo "  ref_files  = '${ref}'"
        echo "  dbfs_files = '${dbfs}'"
        echo "  boot_files = '${boot}'"
        echo ""
        if [[ $(( ${keep} + ${copy} + ${DEBUG} )) -gt 0 ]]; then
            echo "  other options:"
            if [[ ${keep} -ge 1 ]] ; then
                echo "    keep intermediates"
            fi
            if [[ ${copy} -ge 1 ]] ; then
                echo "    copy results to release directory"
            fi
            if [[ ${DEBUG} -ge 1 ]] ; then
                echo "    debug mode enabled"
            fi
            echo ""
        fi
        if [[ ${DEBUG} -ge 1 ]] ; then
            pause "Press <Enter> to continue..."
        fi
    fi


##################
#
# The real work...
#

#    #
#    # If verbose, turn on echo
#    #
#    if [[ ${verbose} -ge 1 || ${DEBUG} -ge 1 ]] ; then
#   set -x
#    fi

    #
    # Check that our generated releasedir resolves to something reasonable, and error
    # if it doesn't
    #
    if [[ ! -e "${releasedir}" ]] ; then
	#
	# Bad generated releasedir
	#
        msg "${myname}: ERROR: The release directory derived from your input paramaters, '${releasedir}', doesn't exist... check the parameters you specified"
	exitcode=4
	usage
    fi

    #
    # Do a first-pass check if the given parameters yield a path to a directory/file
    # that exists. If the subdir doesn't exist, then something eroneous must have
    # been specified and there's no point in continueing.
    #
    # We're going to check one path associated with the engine, and one path associate
    # with the cp. If those both exist, then odds are good that all the other files
    # that we need also exist.
    #
    host_base_url="${sh_base_url}${release_name}/${release_group}/${host_type}_dist_${hwphase}/${host_major_version}.${host_version}/${target}"
    msgv 1 "++ curl --output /dev/null --silent --head --fail \"${host_base_url}\""
    curl --output /dev/null --silent --head --fail "${host_base_url}"
    stat=$?
    if [[ $stat -gt 0 ]] ; then
        msg "${myname}: ERROR: The URL '${host_base_url}' doesn't exist... check the parameters you specified"
        exitcode=4
        usage
    fi

    cp_base_url="${sh_base_url}${release_name}/${release_group}/${guest_type}_dist_${hwphase}/${cp_major_version}.${cp_version}/${target}"
    msgv 1 "++ curl --output /dev/null --silent --head --fail \"${cp_base_url}\""
    curl --output /dev/null --silent --head --fail "${cp_base_url}"
    stat=$?
    if [[ $stat -gt 0 ]] ; then
        msg "${myname}: ERROR: The URL '${cp_base_url}' doesn't exist... check the parameters you specified"
        exitcode=4
        usage
    fi

    #
    # Make sure the specified workdir exists... create it if it doesn't
    #
    if [[ ! -d "${workdir}" ]] ; then
        msg "${myname}: Creating working directory '${workdir}'..."
        mkdir -p "${workdir}"
        stat=$?
        if [[ $stat -gt 0 ]] ; then
            msg "${myname}: ERROR: Unable to create working directory '${workdir}', stat=${stat}"
            exitcode=5
            exit ${exitcode}
        fi
    fi

    #
    # Create our work directories
    #
    if [[ -e "${dbfs}" ]] ; then
        msgv 2 "++ rm -rf \"${dbfs}\""
        rm -rf "${dbfs}"
    fi
    msgv 1 "++ mkdir -p \"${dbfs}\""
    mkdir -p "${dbfs}"

    if [[ -e "${ref}" ]] ; then
        msgv 2 "++ rm -rf \"${ref}\""
        rm -rf "${ref}"
    fi
    msgv 1 "++ mkdir -p \"${ref}\""
    mkdir -p "${ref}"

    if [[ -e "${boot}" ]] ; then
        msgv 2 "++ rm -rf \"${boot}\""
        rm -rf "${boot}"
    fi
    msgv 1 "++ mkdir -p \"${boot}\""
    mkdir -p "${boot}"





  ###########################################################################
  #
    #
    # Get the reference files needed
    #
    msg "${myname}: Downloading necessary files...";
    msg ""

    # partition: "main"
    # download the core host fhx/fhx.info files.
    # and the core boot image which we'll eventually need

        # host lbi.fhx
        host_lbi_fhx_file="${host_type}_dist_${hwphase}_${host_major_version}.${host_version}_${target}_lbi.fhx"
        download "${host_base_url}/${host_lbi_fhx_file}" "${ref}/${host_lbi_fhx_file}"

        # host lbi.fhx.info
        host_lbi_fhx_info_file="${host_type}_dist_${hwphase}_${host_major_version}.${host_version}_${target}_lbi.fhx.info"
        download "${host_base_url}/${host_lbi_fhx_info_file}" "${ref}/${host_lbi_fhx_info_file}"

        # host boot_lbi_rootfs.fhx
        host_boot_lbi_rootfs_fhx_file="${host_type}_dist_${hwphase}_${host_major_version}.${host_version}_${target}_boot_lbi_rootfs.fhx"
        download "${host_base_url}/${host_boot_lbi_rootfs_fhx_file}" "${boot}/${host_boot_lbi_rootfs_fhx_file}"

    # partition: dbfs
    # download the guest cp fhx/fhx.info and 7z rootfs archive
    # changed 20160421: use boot_lbi_rootfs.fhx instead of lbi_rootfs.fhx

        #cp_boot_lbi_rootfs.fhx
        cp_boot_lbi_rootfs_fhx_file="${guest_type}_dist_${hwphase}_${cp_major_version}.${cp_version}_${target}_boot_lbi_rootfs.fhx"
        download "${cp_base_url}/${cp_boot_lbi_rootfs_fhx_file}" "${dbfs}/db_ui.fhx"

        # limo_cp .7z
        #   we're going to put the raw .7z file into the boot directory so that
        #   it won't get in the way of the bundling if we don't delete it.  We'll
        #   unpack it from here into the dbfs directory.
        cp_7z_file="${guest_type}_dist_${hwphase}_${cp_major_version}.${cp_version}_${target}^rootfs_${cp_major_version}.${cp_version}.tar.7z"
        download "${cp_base_url}/${cp_7z_file}" "${boot}/${cp_7z_file}"

    if [[ ${include_datafs} -gt 0 ]]; then
    # partition: datafs
    # download data fhx/fhx.info files

        # host datafs.fhx
        host_datafs_fhx_file="${host_type}_dist_${hwphase}_${host_major_version}.${host_version}_${target}_datafs.fhx"
        download "${host_base_url}/${host_datafs_fhx_file}" "${ref}/${host_datafs_fhx_file}"

        # host datafs.fhx.info
        host_datafs_fhx_info_file="${host_type}_dist_${hwphase}_${host_major_version}.${host_version}_${target}_datafs.fhx.info"
        download "${host_base_url}/${host_datafs_fhx_info_file}" "${ref}/${host_datafs_fhx_info_file}"
    fi
  #
  ###########################################################################

    #
    # unpack the tar.7z
    #

    msg ""
    msg "${myname}: Unpacking .7z file..."
    msgv 1 "++ 7za x -so ${boot}/${cp_7z_file} |  tar x -O '*.bio_dist' > ${dbfs}/.bio_dist 2> /dev/null"
    7za x -so ${boot}/${cp_7z_file} |  tar x -O '*.bio_dist' > ${dbfs}/db_ui.bio_dist 2> /dev/null
    stat=$?
    if [[ $stat -gt 0 ]] ; then
        msg "${myname}: ERROR: Unable to unpack '${cp_7z_file}', status=${stat}"
        exit 5
    fi

    #
    # Create the dbfs image based upon the dbfs directory contents
    #
    msg "${myname}: Creating dbfs image..."
    msg ""

    if [[ -e "${ref}/reflash_dbfs.fhx" ]] ; then
        msgv 2 "++ rm -f \"${ref}/reflash_dbfs.fhx\""
        rm -f "${ref}/reflash_dbfs.fhx"
        msgv 2 "++ rm -f \"${ref}/reflash_dbfs.fhx.info\""
        rm -f "${ref}/reflash_dbfs.fhx.info"
    fi

#?????
    host_dbfs_file="${host_type}_dist_${hwphase}_${host_major_version}.${host_version}_${target}_boot_lbi_rootfs_dbfs.fhx"

    if [[ -e "${workdir}/${host_dbfs_file}" ]] ; then
        msgv 2 "++ rm -f \"${workdir}/${host_dbfs_file}\""
        rm -f "${workdir}/${host_dbfs_file}"
    fi
#?????

    reflash_dbfs_fhx_filename="reflash_dbfs.fhx"
    msgv 1 "++ dir_to_fhx_emmc.rb \"${ref}/${reflash_dbfs_fhx_filename}\" \"${dbfs}\" \"${ref}/${host_lbi_fhx_file}\" dbfs"
    dir_to_fhx_emmc.rb "${ref}/${reflash_dbfs_fhx_filename}" "${dbfs}" "${ref}/${host_lbi_fhx_file}" dbfs
    stat=$?
    if [[ $stat -gt 0 ]] ; then
        msg "${myname}: ERROR: Failure from dir_to_fhx_emc.rb, status=${stat}"
        exit 5
    fi

    #
    # Combine the load images
    #
    fhxs_to_combine=( "${ref}/reflash_dbfs.fhx" )
    combined_filename="${destdir}/${host_type}_dist_${hwphase}_${host_major_version}.${host_version}_${target}_boot_lbi_rootfs"
    if [[ ${include_datafs} -gt 0 ]]; then
        combined_filename="${combined_filename}_datafs"
        fhxs_to_combine[${#fhxs_to_combine[@]}]="${ref}/${host_datafs_fhx_file}"
    fi

    if [[ ${include_recoveryfs} -gt 0 ]]; then
        combined_filename="${combined_filename}_recovery"
        fhxs_to_combine[${#fhxs_to_combine[@]}]="${ref}/${host_recoveryfs_fhx_file}"
    fi
    combined_filename="${combined_filename}_dbfs.fhx"

    if [[ -e "${combined_filename}" ]] ; then
        msgv 2 "++ rm -f \"${combined_filename}\""
        rm -f "${combined_filename}"
    fi

    msg "${myname}: Combining load images into '${combined_filename}'"

    msgv 1 "++ multiple_fhxs_to_one_fhx.ksh \"${boot}/${host_boot_lbi_rootfs_fhx_file}\" \"${combined_filename%.*}\" \"${fhxs_to_combine[*]}\""
    multiple_fhxs_to_one_fhx.ksh "${boot}/${host_boot_lbi_rootfs_fhx_file}" "${combined_filename%.*}" "${fhxs_to_combine[@]}"
    stat=$?
    if [[ $stat -gt 0 ]] ; then
        msg "${myname}: ERROR: Failure from multiple_fhxs_to_fhx.ksh, status=${stat}"
        exit 5
    fi

    #
    # If requested, copy the bundled file into the release directory
    #
    if [[ ${copy} -ge 1 ]] ; then
        #
        # Copy the file into place
        #
        msg "${myname}: Copying bundled image into release directory..."
        msg "\n\n"
        msg "================================================================="
        msg "=====  PLEASE REVIEW THE FOLLOWING AND CONFIRM TO CONTINUE  ====="
        msg "================================================================="
        msg "" 
        msg "Proposed:"
        msg "    Copy file:    ${combined_filename}"
        msg "    To directory: ${releasedir}"
        msg ""
        ( { set +x; } 2>/dev/null; pause "Hit <Enter> to confirm; Ctrl-C to abort the copy..." )
        if [[ ${DEBUG} -ge 1 ]] ; then
            msg "(DEBUG) NOT PERFORMED: cp \"${combined_filename}\" \"${releasedir}\""
        else
            msgv 2 "++ cp \"${combined_filename}\" \"${releasedir}\""
            cp "${combined_filename}" "${releasedir}"
        fi
    fi


    #
    # Clean up intermediate files/directories
    #
    if [[ ${keep} -ne 1 ]] ; then
        msg "${myname}: Cleaning up..."
        msgv 2 "++ rm -rf \"${workdir}\""
        rm -rf "${workdir}"
    else
        msg "${myname}: Note: keeping intermediate files and directories..."
    fi


    #
    # And we're done.  Clean up and exit
    #
    msg "${myname}: Done"
    exit ${exitcode}

