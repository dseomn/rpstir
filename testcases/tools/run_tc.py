#!/usr/bin/env python

# Run test cases using test driver file test.conf
# open test driver file
#  -- run through every line in the file and perform the specified function
#     For BBN this means using the rcli and query programs to insert/delete
#     certificates from the database or query the database for the cert
#     cases:
#      PATH - set the certificate path
#      ECHO - just print this string to stdout
#      INSERT - insert this certificate into the database
#      DELETE - delete this certificate from the database
#      DISPLAY - query the database for this certificate

import os
import sys
import traceback
import subprocess
from optparse import OptionParser

global certpath
global verbose

def err(code, errstring):
    print errstring    
    sys.exit(code)


def run_tests(cfgfile):
    """ run all test cases"""

    # open test config file
    try:
        if not os.path.exists(cfgfile):
            err(1,("Test configuration file does not exist: %s") % (cfgfile))

        file = open(cfgfile)
        for line in file:
            if not line.startswith("#") and len(line) > 1:
                process_input(line)


    except IOError:
        traceback.print_exc()
        error(1,("Error processing file %s") % (cfgfile))
        

    return

def process_input(line):
    """
    Process line from input configuration file.
    split the command into fields separated by space
    The first field is the command. Subsequent fields are
    based upon the command.
    """
    global certpath
    
    line = line.strip()
#    print line
    fields = line.split(' ')
    # convert command to upper case to compare
    command = fields[0].upper()
    # switch based upon command

    # add the certificate to the repository
    if command == ('ADD'):
        cert = fields[1]
        trusted = False
        if len(fields) > 2:
            if fields[2].upper().startswith('TRUSTED'):
                trusted = True
        add_to_repository(cert, trusted)

    # delete certificate from the repository
    elif command == 'DELETE':
        cert = fields[1]
        del_from_repository(cert)

    # echo the line directly from config file 
    elif command == 'ECHO':
        print ('%s') % (line.strip(command))
    
    # display cert in database and print pass or fail
    # based upon expected results (from command line)
    elif command == 'DISPLAY':
        result = False
        cert = fields[1]
        if fields[2].lower() == 'true':
            result = True
        display_cert(cert,result)


    elif command == 'PATH':
        if os.path.exists(fields[1]):
            certpath = fields[1]
            print ('Certificate path set to %s ') % (certpath)
        else:
            print ('Path %s does not exist') % (fields[1])

    else:
        return

    return

def display_cert(cert, result):
    """
    Query the repository to see if the certificate is there - compare
    parse query results looking for cert - 
     if there and expected result true then print PASS with flags
     if there and expected result false then print FAIL
     if not there and expected result true then print FAIL
     if not there and expected result false then print PASS

    BBN software case:
       query -t cert -d filename -d flags
    """

    if cert is None:
        return

    command = ('query -t cert -d filename -d flags')
    out, err = exec_command(command)
    if out is not None:
        if cert in out:
            if result:
                print ("%s: PASS") % (cert)
            else:
                print ("%s: FAIL") % (cert)
        else:
            if result:
                print ("%s: FAIL") % (cert)
            else:
                print ("%s: PASS") % (cert)

    if err is not None:
        print err
    return    


def add_to_repository(cert, trusted):
    """
    Add certificate to repository
    BBN softrware case:
      run rcli command to add certificate to database (rcli -y -f cert)
    """

    global verbose
    
    if cert is None:
        return

    fullpath_cert = create_fullpath_cert(cert)
    if trusted:
        command = ("rcli -y -F %s") % (fullpath_cert)
    else:
        command = ("rcli -y -f %s") % (fullpath_cert)
    out, err = exec_command(command)
    
    if verbose and err is not None:
        print err
    return

def del_from_repository(cert):
    """ 
    Delete certificate from the database
    BBN software case:
       run rcli command to delete certificate from the database
       rcli -y -d <cert>
    """

    if cert is None:
        return

    fullpath_cert = create_fullpath_cert(cert)

    command = ("rcli -y -d %s") % (fullpath_cert)
    out,err = exec_command(command)

    return

def create_fullpath_cert(cert):
    """create a full pathname for the cert if it isn't already one
    """
    global certpath

    # if it starts with a full / then it must already be a fullpath name
    if cert.startswith('/'):
        return cert

    if certpath is None:
        return cert

    # join pathname with certificate name, add slash if necessary
    if certpath.endswith("/"):
        fullpath_cert = ("%s%s") % (certpath, cert)
    else:
        fullpath_cert = ("%s/%s") % (certpath, cert)

    return fullpath_cert


def exec_command(cmd):
    """ execute the specified command
    """

    p = subprocess.Popen(cmd, shell=True, stdout = subprocess.PIPE,
                         stderr = subprocess.PIPE)
    out,err = p.communicate()
    return( out, err )


def main(argv=None):
    
    usage = """usage: %prog [options] <test.conf> 
    Run all test cases specified in the test configuration file 
    """

    global verbose

    if argv is None:
        argv = sys.argv

    parser = OptionParser(usage)
    parser.add_option("-q", "--quiet",
                  action="store_false", dest="verbose", default=True,
                  help="don't print status messages to stdout")

    opts,args = parser.parse_args()
    verbose = opts.verbose

    if len(argv) < 2:
        parser.error('Missing Test Configuration File')
        parser.print_usage()
        sys.exit(-1)

    config_file = args[0]
    run_tests(config_file)

if __name__ == "__main__":
    sys.exit(main())
