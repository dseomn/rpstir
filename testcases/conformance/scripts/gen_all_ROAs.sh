#!/bin/bash

# gen_all_ROAs.sh - create all ROA test cases for RPKI syntactic
#                   conformance test

# Set up RPKI environment variables if not already done.
THIS_SCRIPT_DIR=$(dirname $0)
. $THIS_SCRIPT_DIR/../../../envir.setup

# Safe bash shell scripting practices
. $RPKI_ROOT/trap_errors

# Usage
usage ( ) {
    usagestr="
Usage: $0 [options]

Options:
  -P        \tApply patches instead of prompting user to edit (default = false)
  -h        \tDisplay this help file

This script creates a large number of ROAs (with embedded EE certs),
prompts the user multiple times to edit interactively (e.g., in order
to introduce errors), and captures those edits in '.patch' files
(output of diff -u).  Later, running $0 with the -P option can replay
the creation process by automatically applying those patch files
instead of prompting for user intervention.  In patch mode, existing
keys are reused from the keys directory, instead of the default of
generating new keys.

This tool assumes the repository structure in the diagram below.  It
creates a ton of ROAs (with embedded EE certs).  In the EE certs' SIA, the
accessMethod id-ad-signedObject will have an accessLocation of
rsync://rpki.bbn.com/conformance/root/subjname.roa.

NOTE: this script does NOT update the manifest issued by root.

               +-----------------------------------+
               | rsync://rpki.bbn.com/conformance/ |
               |     +--------+                    |
         +---------->|  Root  |                    |
         |     |     |  cert  |                    |
         |     |     |  SIA ----------------------------+
         |     |     +---|----+                    |    |
         |     +---------|-------------------------+    |
         |               |                              |
         |               V                              |
         |     +----------------------------------------|----+
         |     | rsync://rpki.bbn.com/conformance/root/ |    |
         |     |                                        V    |
         |     | +-------------+       +-----------------+   |
         |     | | *ROA issued |<--+   | Manifest issued |   |
         |     | | by Root     |   |   | by Root         |   |
         |     | | +--------+  |   |   | root.mft        |   |
         |     | | | EECert |  |   |   +-----------------+   |
         +----------- AIA   |  |   |                         |
               | | |  SIA ---------+       +------------+    |
               | | |  CRLDP--------------->| CRL issued |    |
               | | +--------+  |           | by Root    |    |
               | +-------------+           | root.crl   |    |
               |                           +------------+    |
               | Root's Repo                                 |
               | Directory                                   |
               +---------------------------------------------+

Inputs:
  -P - (optional) use patch mode for automatic insertion of errors

Outputs:
  ROA - AS/IP is hardcoded in goodCert.raw and goodROA templates
  patch files - manual edits are saved as diff output in
                'badROA<filestem>.stageN.patch' (N=0..1) in the patch
                directory
  key files - generated key pairs for the EE certs are stored in keys directory
              as badROA<filestem>.ee.p15
    "
    printf "${usagestr}\n"
    exit 1
}

# NOTES

# Variable naming convention -- preset constants and command line
# arguments are in ALL_CAPS.  Derived/computed values are in
# lower_case.

# Set up paths to ASN.1 tools.
CGTOOLS=$RPKI_ROOT/cg/tools	# Charlie Gardiner's tools

# Options and defaults
OUTPUT_DIR="$RPKI_ROOT/testcases/conformance/raw/root"
USE_EXISTING_PATCHES=

# Process command line arguments.
while getopts Ph opt
do
  case $opt in
      P)
	  USE_EXISTING_PATCHES=1
	  ;;
      h)
	  usage
	  ;;
  esac
done
shift $((OPTIND - 1))
if [ $# != "0" ]
then
    usage
fi

###############################################################################
# Computed Variables
###############################################################################

if [ $USE_EXISTING_PATCHES ]
then
    patch_option="-P"
else
    patch_option=
fi

single_ROA_script="$RPKI_ROOT/testcases/conformance/scripts/make_test_CMS.sh"
single_ROA_cmd="${single_ROA_script} ${patch_option} -o ${OUTPUT_DIR}"

###############################################################################
# Check for prerequisite tools and files
###############################################################################

ensure_file_exists ( ) {
    if [ ! -e "$1" ]
    then
	echo "Error: file not found - $1" 1>&2
	exit 1
    fi
}

ensure_dir_exists ( ) {
    if [ ! -d "$1" ]
    then
	echo "Error: directory not found - $1" 1>&2
	exit 1
    fi
}

ensure_dir_exists "$OUTPUT_DIR"
ensure_dir_exists "$CGTOOLS"
ensure_file_exists "${single_ROA_script}"

###############################################################################
# Generate ROA cases
###############################################################################

${single_ROA_cmd} -x good ROA 550 NothingWrong
${single_ROA_cmd} ROA 551 ASIDSmall
${single_ROA_cmd} ROA 552 ASIDLarge
${single_ROA_cmd} ROA 553 Family
${single_ROA_cmd} ROA 554 FamilyLth
${single_ROA_cmd} ROA 555 IPv4MaxLthLong
${single_ROA_cmd} ROA 556 IP2Big
${single_ROA_cmd} ROA 557 VersionV1Explicit
${single_ROA_cmd} ROA 558 VersionV1ExplicitBadSig
${single_ROA_cmd} ROA 559 VersionV2
