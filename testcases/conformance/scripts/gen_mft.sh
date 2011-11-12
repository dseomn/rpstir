#!/bin/bash

# Set up RPKI environment variables if not already done.
THIS_SCRIPT_DIR=$(dirname $0)
. $THIS_SCRIPT_DIR/../../../envir.setup

# Safe bash shell scripting practices - exit w/ failure on any error
. $RPKI_ROOT/trap_errors

# Usage
usage ( ) {
    usagestr="
Usage: $0 [options] <subjectname> <eeserial> <mftnum> \\
\t<parentcertfile> <parentURI> <parentkeyfile> <crldp> [file1 ...]

Options:
  -o outdir\tOutput directory (default = CWD)
  -h       \tDisplay this help file

This tool takes as input a parent CA certificate + key pair, and as
output, issues a manifest covering the files listed on input.  The
diagram below shows outputs of the script.  The inputs and
non-participants are indicated by normal boxes; the outputs are
indicated by boxes whose label has a prepended asterisk (*).

                    +--------+
                    | Parent |
                    |  AIA   |
            +--------- SIA------------+
            |       +--------+        |
            |                         |
            |  +----------------------|---------------+
            |  |                      |               |
            +->| +-------+  +-------+ |  +-------+    |
               | | file1 |  | file2 | |  | file3 |    |
               | +-------+  +-------+ |  +-------+    |
               |                      |               |
               |                      V               |
               |                  +-----------------+ |
               |                  | * MFT issued by | |
               | Parent's Repo    |   Parent        | |
               | Directory        +-----------------+ |
               +--------------------------------------+

Inputs:
  subjectname - subject name for the child
  eeserial - serial number for the embedded EE cert
  mftnum - manifest number
  parentcertfile - local path to parent certificate file
  parentURI - full rsync URI to parent certificate file
  parentkeyfile - local path to parent key pair (.p15 file)
  crldp - full rsync URI to 'CRL issued by Parent'.  Probably something like
          <parentSIA>/<parentSubjectName>.crl
  outdir - (optional) local path to parent's repo directory.  Defaults to CWD

Outputs:
  mft issued by parent - <outdir>/<subjectname>.mft, with 0 or more entries

Auxiliary Outputs: (not shown in diagram)
  MFT EE cert - <outdir>/<subjectname>.mft.cer
  MFT EE key pair - <outdir>/<subjectname>.mft.p15

Example:
./gen_mft.sh root 1 1 ../raw/root.cer rsync://rpki.bbn.com/conformance/root.cer ../raw/root.p15 rsync://rpki.bbn.com/conformance/root/root.crl *
    "
    printf "${usagestr}\n"
    exit 1
}

# NOTES
# 1. Variable naming convention -- preset constants and command line
# arguments are in ALL_CAPS.  Derived/computed values are in
# lower_case.
# 2. Dependencies: This script assumes the existence (and PATH
# accessibility) of the standard tools 'sed' and 'sha256sum'.

# Set up paths to ASN.1 tools.
CGTOOLS=$RPKI_ROOT/cg/tools	# Charlie Gardiner's tools
TBTOOLS=$RPKI_ROOT/testbed/src	# Tools used for testbed generation

# Options and defaults
OUTPUT_DIR="."
EECERT_TEMPLATE="$RPKI_ROOT/testbed/templates/ee_template.cer"
CRL_TEMPLATE="$RPKI_ROOT/testbed/templates/crl_template.crl"
MFT_TEMPLATE="$RPKI_ROOT/testbed/templates/M.man"

# Process command line arguments.
while getopts o:h opt
do
  case $opt in
      o)
	  OUTPUT_DIR=$OPTARG
	  ;;
      h)
	  usage
	  ;;
  esac
done
shift $((OPTIND - 1))
if [ $# -ge 7 ]
then
    SUBJECTNAME=$1
    EE_SERIAL=$2
    MFT_NUM=$3
    PARENT_CERT_FILE=$4
    PARENT_URI=$5
    PARENT_KEY_FILE=$6
    CRLDP=$7
    shift 7
else
    usage
fi

###############################################################################
# Check for prerequisite tools
###############################################################################

# Ensure executables are in PATH
hash sha256sum
hash sed
hash basename

ensure_file_exists $CGTOOLS/extractSIA
ensure_file_exists $CGTOOLS/extractValidityDate
ensure_file_exists $CGTOOLS/gen_key
ensure_file_exists $TBTOOLS/create_object

compute_sha256 ( ) {
    ensure_file_exists $1
    echo $(sha256sum "$1" | sed -e 's/ .*$//' -e 'y/abcdef/ABCDEF/')
}

###############################################################################
# Check for prerequisite files
###############################################################################

ensure_dir_exists $OUTPUT_DIR
ensure_file_exists ${PARENT_CERT_FILE}
ensure_file_exists ${PARENT_KEY_FILE}
ensure_file_exists ${EECERT_TEMPLATE}

###############################################################################
# Compute Paths (both rsync URIs and local paths)
###############################################################################

# Extract SIA manifest URI from parent
parent_sia=$($CGTOOLS/extractSIA -m $PARENT_CERT_FILE)
echo "Parent SIA: ${parent_sia}"

# Extract validity dates from parent in both X.509 (utctime or gmtime,
# depending on the date) and MFT (gmtime) formats.
parent_notbefore=$($CGTOOLS/extractValidityDate -b $PARENT_CERT_FILE)
parent_notafter=$($CGTOOLS/extractValidityDate -a $PARENT_CERT_FILE)
parent_notbefore_gtime=$($CGTOOLS/extractValidityDate -b -g $PARENT_CERT_FILE)
parent_notafter_gtime=$($CGTOOLS/extractValidityDate -a -g $PARENT_CERT_FILE)

# Compute SIA manifest URI for EE cert
ee_sia_mft="${parent_sia}"

# Compute manifest filename
mft_name="${SUBJECTNAME}.mft"
if [ $(basename "$ee_sia_mft") != $mft_name ]
then
    echo "Warning: output filename ($mft_name) does not match" \
        "parent's SIA MFT field ($ee_sia_mft)" 1>&2
fi

# Compute local output paths
mft_path=${OUTPUT_DIR}/${mft_name}
mft_ee_path=${OUTPUT_DIR}/${mft_name}.cer
mft_ee_key_path=${OUTPUT_DIR}/${mft_name}.p15

###############################################################################
# Generate EE cert and Manifest
###############################################################################

# 1. Generate EE key pair
$CGTOOLS/gen_key $mft_ee_key_path 2048
echo "Generated MFT EE key pair: $mft_ee_key_path"

# 2. Create child-issued EE cert (to be embedded in the manifest)
$TBTOOLS/create_object -t ${EECERT_TEMPLATE} CERT \
    outputfilename=${mft_ee_path} \
    parentcertfile=${PARENT_CERT_FILE} \
    parentkeyfile=${PARENT_KEY_FILE} \
    subjkeyfile=${mft_ee_key_path} \
    type=EE \
    notbefore=${parent_notbefore} \
    notafter=${parent_notafter} \
    serial=${EE_SERIAL} \
    subject="${SUBJECTNAME}-mft-ee" \
    crldp=${CRLDP} \
    aia=${PARENT_URI} \
    sia="m:${ee_sia_mft}" \
    ipv4=inherit \
    ipv6=inherit \
    as=inherit
echo "Created MFT EE certificate: ${mft_ee_path}"

# 3. Compute file-and-hash list
fileandhashlist=''
firstfile=true
while [ $# -gt 0 ]; do
    if [ $firstfile = 'true' ]; then
        firstfile=false
    else
        fileandhashlist="$fileandhashlist",
    fi
    fileandhashlist="$fileandhashlist"$(basename $1)'%0x'$(compute_sha256 $1)
    shift
done

# 4. Create child-issued Manifest
$TBTOOLS/create_object -t ${MFT_TEMPLATE} MANIFEST \
    outputfilename=${mft_path} \
    EECertLocation=${mft_ee_path} \
    EEKeyLocation=${mft_ee_key_path} \
    thisUpdate=${parent_notbefore_gtime} \
    nextUpdate=${parent_notafter_gtime} \
    manNum=${MFT_NUM} \
    filelist=$fileandhashlist
echo "Created child-issued MFT: ${mft_path}"
