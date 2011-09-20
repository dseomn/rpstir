#!/bin/bash
#
# ***** BEGIN LICENSE BLOCK *****
#
#  BBN Address and AS Number PKI Database/repository software
#  Version 4.0
#
#  US government users are permitted unrestricted rights as
#  defined in the FAR.
#
#  This software is distributed on an "AS IS" basis, WITHOUT
#  WARRANTY OF ANY KIND, either express or implied.
#
#  Copyright (C) Raytheon BBN Technologies 2011.  All Rights Reserved.
#
#  Contributor(s): Charlie Gardiner, Andrew Chi
#
#  ***** END LICENSE BLOCK ***** */

# make_test_CRL.sh - manually create CertificateRevocationList (CRL)
#       for RPKI syntax conformance test

# Set up RPKI environment variables if not already done.
THIS_SCRIPT_DIR=$(dirname $0)
. $THIS_SCRIPT_DIR/../../../envir.setup

# Safe bash shell scripting practices
. $RPKI_ROOT/trap_errors

# Usage
usage ( ) {
    usagestr="
Usage: $0 [options] <serial> <subjectname>

Options:
  -P        \tApply patches instead of prompting user to edit (default = false)
  -k keyfile\tRoot's key (default = ...conformance/raw/root.p15)
  -o outdir \tOutput directory (default = ...conformance/raw/root)
  -p patchdir\tDirectory for saving/getting patches (default = ...conformance/raw/patches
  -d keydir\tDirectory for saving/getting keys (default = ...conformance/raw/keys)
  -x prefix\tPrefix (default = 'bad')
  -h        \tDisplay this help file

This script creates a CRL, prompts the user multiple times to edit it
interactively (e.g., in order to introduce errors), and captures
those edits in '.patch' files (output of diff -u).  Later,
make_test_CRL.sh can replay the creation process by automatically
applying those patch files instead of prompting for user intervention.

This tool takes as input a parent CA certificate + key pair, and as
output, issues a child CA certificate with a minimal publication
subdirectory.  The diagram below shows outputs of the script.  The
inputs and non-participants are indicated by normal boxes; the outputs
are indicated by boxes whose label has a prepended asterisk (*).
Note: this script does NOT update the 'Manifest issued by Parent'.


               +-----------------------------------+
               | rsync://rpki.bbn.com/conformance/ |
               |    +--------+                     |
         +--------->|  Root  |                     |
         |     |    |  AIA   |                     |
         |     |    |  SIA   |                     |
         |     |    +---|----+                     |
         |     +--------|--------------------------+
         |              V
         |     +----------------------------------------+
         |     | rsync://rpki.bbn.com/conformance/root/ |
         |     |   +--------+     +------------+        |
         |     |   | *Child |     | CRL issued |        |
         |     |   | CRLDP------->| by Parent  |        |
         +----------- AIA   |     +------------+        |
               |   |  SIA------+                        |
               |   +--------+  |  +-----------------+   |
               |               |  | Manifest issued |   |
               | Root's Repo   |  | by Parent       |   |
               | Directory     |  +-----------------+   |
               +---------------|------------------------+
                               |
                               V
	     +-------------------------------------------------+
       	     | rsync://rpki.bbn.com/conformance/root/subjname/ |
             |                                     	       |
             |     +---------------------------+   	       |
             |     | *Manifest issued by Child |               |
             |     +---------------------------+               |
             |                                                 |
             |     +----------------------------------+        |
             |     | *CRL issued by Child (TEST CASE) |        |
             |     +----------------------------------+        |
             |                                                 |
             | *Child's Repo Directory                         |
             +-------------------------------------------------+

Explanation of inputs, not in original order:
  subjectname - subject name for the child
  serial - serial number for the child to be created
  -P - (optional) use patch mode for automatic insertion of patches
  patchdir - (optional) local path to directory of patches
  outdir - (optional) local path to parent's repo directory.  Defaults to CWD

Outputs:
  child CA certificate - inherits AS/IP resources from parent via inherit bit
  path files - manual edits are saved as diff output in
              'badCRL<subjectname>.stageN.patch' (N=0..1)

  child repo directory - ASSUMED to be a subdirectory of parent's repo. The
                         new directory will be <outdir>/<subjectname>/
  crl issued by child - named <subjectname>.crl, and has no entries
  mft issued by child - named <subjectname>.mft, and has one entry (the crl)

  The filename for the crl will be prepended by the string 'bad' by
  default, though this can be replaced by an arbitrary non-empty
  string using the -x option.

Auxiliary Outputs: (not shown in diagram)
  child key pair - <outdir>/<subjectname>.p15
  child-issued MFT EE cert - <outdir>/<subjectname>/<subjectname>.mft.cer
  child-issued MFT EE key pair - <outdir>/<subjectname>/<subjectname>.mft.p15
    "
    printf "${usagestr}\n"
    exit 1
}

# NOTES

# 1. Variable naming convention -- preset constants and command line
# arguments are in ALL_CAPS.  Derived/computed values are in
# lower_case.

# 2. Assumes write-access to current directory even though the output
# directory will be different.

# Set up paths to ASN.1 tools and conformance test scripts
CGTOOLS=$RPKI_ROOT/cg/tools	# Charlie Gardiner's tools
CONF_SCRIPTS=$RPKI_ROOT/testcases/conformance/scripts

# Options and defaults
OUTPUT_DIR="$RPKI_ROOT/testcases/conformance/raw/root"
PATCHES_DIR="$RPKI_ROOT/testcases/conformance/raw/patches"
KEYS_DIR="$RPKI_ROOT/testcases/conformance/raw/keys"
ROOT_KEY_PATH="$RPKI_ROOT/testcases/conformance/raw/root.p15"
ROOT_CERT_PATH="$RPKI_ROOT/testcases/conformance/raw/root.cer"
USE_EXISTING_PATCHES=
PREFIX="bad"
EDITOR=${EDITOR:-vi}            # set editor to vi if undefined
# Process command line arguments.
while getopts Pk:o:p:d:x:h opt
do
  case $opt in
      P)
	  USE_EXISTING_PATCHES=1
	  ;;
      k)
	  ROOT_KEY_PATH=$OPTARG
	  ;;
      o)
	  OUTPUT_DIR=$OPTARG
	  ;;
      p)
          PATCHES_DIR=$OPTARG
          ;;
      d)
          KEYS_DIR=$OPTARG
          ;;
      x)
          PREFIX=$OPTARG
          ;;
      h)
	  usage
	  ;;
  esac
done
shift $((OPTIND - 1))
if [ $# = "2" ]
then
    SERIAL=$1
    SUBJECTNAME=$2
else
    usage
fi

###############################################################################
# Computed Variables
###############################################################################

child_name="${SUBJECTNAME}"
crl_name="${PREFIX}${child_name}"


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

hash patch
hash diff

ensure_dir_exists $OUTPUT_DIR
ensure_dir_exists $PATCHES_DIR

ensure_file_exists $ROOT_KEY_PATH
ensure_file_exists $ROOT_CERT_PATH
ensure_file_exists $CGTOOLS/rr
ensure_file_exists $CGTOOLS/dump
ensure_file_exists $CGTOOLS/dump_smart
ensure_file_exists $CGTOOLS/sign_cert
ensure_file_exists $CGTOOLS/fix_manifest
ensure_file_exists $CONF_SCRIPTS/gen_child_ca.sh

if [ $USE_EXISTING_PATCHES ]
then
    ensure_file_exists $PATCHES_DIR/${crl_name}.stage0.patch
    ensure_file_exists $PATCHES_DIR/${crl_name}.stage1.patch
fi

###############################################################################
# Generate Child cert
###############################################################################

cd ${OUTPUT_DIR}

# Create a good CRL in a subdirectory (but named <prefix><subjname>.crl)
$CONF_SCRIPTS/gen_child_ca.sh \
    -b crl \
    -o ${OUTPUT_DIR} \
    -x ${PREFIX} \
    ${child_name} \
    ${SERIAL} \
    ${ROOT_CERT_PATH} \
    rsync://rpki.bbn.com/conformance/root.cer \
    ${ROOT_KEY_PATH} \
    rsync://rpki.bbn.com/conformance/root/root.crl

# Go into that subdirectory...
cd ${OUTPUT_DIR}/${child_name}
${CGTOOLS}/dump_smart ${crl_name}.crl >${crl_name}.crl.raw

# Stage 0: Pre-signing modification: manual or automatic (can be no-op)
if [ $USE_EXISTING_PATCHES ]
then
    echo "Stage 0: Modify to-be-signed portions automatically"
    patch ${crl_name}.crl.raw ${PATCHES_DIR}/${crl_name}.stage0.patch
    rm -f ${crl_name}.crl.raw.orig
else
    echo "Stage 0: Modify to-be-signed portions manually"
    cp ${crl_name}.crl.raw ${crl_name}.crl.raw.old
    ${EDITOR} ${crl_name}.crl.raw
    diff -u ${crl_name}.crl.raw.old ${crl_name}.crl.raw \
	>${PATCHES_DIR}/${crl_name}.stage0.patch || true
fi

# Sign it
echo "Signing CRL"
${CGTOOLS}/rr <${crl_name}.crl.raw >${crl_name}.blb
${CGTOOLS}/sign_cert ${crl_name}.blb ../${child_name}.p15
mv ${crl_name}.blb ${crl_name}.crl
${CGTOOLS}/dump -a ${crl_name}.crl >${crl_name}.crl.raw

# Stage 1: Post-signing modification: manual or automatic (can be no-op)
if [ $USE_EXISTING_PATCHES ]
then
    echo "Stage 1: Modify not-signed portions automatically"
    patch ${crl_name}.crl.raw ${PATCHES_DIR}/${crl_name}.stage1.patch
    rm -f ${crl_name}.crl.raw.orig
else
    echo "Stage 1: Modify not-signed portions manually"
    cp ${crl_name}.crl.raw ${crl_name}.crl.raw.old
    ${EDITOR} ${crl_name}.crl.raw
    diff -u ${crl_name}.crl.raw.old ${crl_name}.crl.raw \
	>${PATCHES_DIR}/${crl_name}.stage1.patch || true
fi

# Convert back into DER-encoded binary
${CGTOOLS}/rr <${crl_name}.crl.raw >${crl_name}.crl

# Update manifest with hash of newly edited CRL
${CGTOOLS}/fix_manifest ${child_name}.mft \
    ${child_name}.mft.p15 ${crl_name}.crl
echo "Updated manifest ${child_name}.mft with hash of ${crl_name}.crl"

# Clean-up
rm ${crl_name}.crl.raw
if [ ! $USE_EXISTING_PATCHES ]
then
    rm ${crl_name}.crl.raw.old
fi

# Notify user of output locations
echo Successfully created "${OUTPUT_DIR}/${child_name}/${crl_name}.crl" and \
    auxiliary files.
if [ ! $USE_EXISTING_PATCHES ]
then
    echo Successfully created "${PATCHES_DIR}/${crl_name}.stage0.patch"
    echo Successfully created "${PATCHES_DIR}/${crl_name}.stage1.patch"
fi
