#
#! /usr/bin/python
#from __future__ import absolute_import
#from __future__ import print_function
import argparse
import sys
import os
#import ROOT
#import samweb_cli
#import requests
import http.client
import ssl
import samweb_client
import hashlib
import zlib
import time
import calendar
import json
import subprocess
import random
import base64

validActions = ["tape", "disk", "scratch", "sam"]

mu2eff = {"raw":"phy-raw",
          "rec":"phy-rec",
          "ntd":"phy-ntd",
          "cnf":"phy-etc",
          "sim":"phy-sim",
          "dts":"phy-sim",
          "mix":"phy-sim",
          "dig":"phy-sim",
          "mcs":"phy-sim",
          "nts":"phy-nts",
          "log":"phy-etc",
          "bck":"phy-etc",
          "etc":"phy-etc"}


userff = {"raw":"phy-raw",
          "rec":"usr-dat",
          "ntd":"usr-dat",
          "ext":"usr-dat",
          "rex":"usr-dat",
          "xnt":"usr-dat",
          "cnf":"usr-etc",
          "sim":"usr-sim",
          "dts":"usr-sim",
          "mix":"usr-sim",
          "dig":"usr-sim",
          "mcs":"usr-sim",
          "nts":"usr-nts",
          "log":"usr-etc",
          "bck":"usr-etc",
          "etc":"usr-etc"}

locprefix = {"tape":"/pnfs/mu2e/tape",
             "disk":"/pnfs/mu2e/persistent/datasets",
             "scratch":"/pnfs/mu2e/scratch/datasets",
             "sam":""}


class DataFile:
    def __init__(self):
        # from input
        self.action = ""
        self.localfs = ""
        self.parents = ""
        # derived
        self.fn = ""
        self.path = ""
        self.samdisk = ""
        self.url = ""
        self.isLog = False
        self.dosam = False
        self.docopy = False
        self.donesam = False
        self.donecopy = False
        self.samtime = -1 # -1=unknown, 0=this process wrote, >0 actual age
        self.copytime = -1
        self.samInfo = {} # from reading sam record
        self.metadata = {} # locally-constructed metadata
        self.locations = [] # from reading sam record
        self.dcacheInfo = {} # from reading dcache database
    def __str__(self):
        ss = "\n>> "+self.fn
        ss = ss+"\n   action  = "+self.action
        ss = ss+"\n   localfs  = "+self.localfs
        ss = ss+"\n   parents  = "+self.parents
        ss = ss+"\n   fn  = "+self.fn
        ss = ss+"\n   path  = "+self.path
        ss = ss+"\n   samdisk  = "+self.samdisk
        ss = ss+"\n   url  = "+self.url
        ss = ss+"\n   isLog  = "+str(self.isLog)
        ss = ss+"\n   dosam  = "+str(self.dosam)
        ss = ss+"\n   docopy  = "+str(self.docopy)
        ss = ss+"\n   donesam  = "+str(self.donesam)
        ss = ss+"\n   donecopy  = "+str(self.donecopy)
        ss = ss+"\n   samtime  = "+str(self.samtime)
        ss = ss+"\n   copytime  = "+str(self.copytime)
        ss = ss+"\n   samInfo  = "+str(self.samInfo)
        ss = ss+"\n   metadata  = "+str(self.metadata)
        ss = ss+"\n   locations  = "+str(self.locations)
        ss = ss+"\n   dcacheInfo  = "+str(self.dcacheInfo)
        return ss


#
#
#
def teeDate(level,m):
    '''
    Print date and message to stdout and stderr
    '''
    if verbose < level :
        return
    tm = "[" + time.ctime() + "] " + m
    print(tm)
    if not ( sys.stdin and sys.stdin.isatty() ) :
        print(tm,file=sys.stderr)
    return

#
#
#
def getToken():
    '''
    Lookup bearer token file and return the encoded token string.
    Search, in order
       1. $BEARER_TOKEN
       2. $BEARER_TOKEN_FILE
       3. $XDG_RUNTIME_DIR/bt_u$UID

    Returns:
        token (str) : the coded token

    Raises:
        FileNotFoundError : for token file not found
        RuntimeError : token was expired
    '''

    token = None
    tokenFile = None
    if 'BEARER_TOKEN' in os.environ :
        token = os.environ['BEARER_TOKEN']
    elif 'BEARER_TOKEN_FILE' in os.environ :
        tokenFile = os.environ['BEARER_TOKEN_FILE']
    elif 'XDG_RUNTIME_DIR' in os.environ :
        tokenFile = os.environ['XDG_RUNTIME_DIR'] + "/bt_u" + str(os.getuid())

    if token == None and tokenFile != None :
        with open(tokenFile, 'r') as file:
            token = file.read().replace('\n', '')

    if token == None :
        raise FileNotFoundError("token file not found")

    token = token.replace("\n","")

    subtoken = token.split(".")[1]
    dectoken = base64.b64decode(subtoken+'==',altchars="_-").decode("utf-8")
    ddtoken = json.loads(dectoken)

    deltat = int(ddtoken['exp']) - int(time.time())
    if deltat < 10 :
        raise RuntimeError("token was expired")

    return token

#
# fill the DataFile object from the input text file
# return 0 for sucess, 2 for fail
#
def fillDataFile(line):

    icc = line.find("#")
    if icc >= 0 :
        line = line[0:icc].strip()
    if len(line) == 0 :
        return
    if verbose >= 1 :
        print("processing: " +  line, end="")

    dfile = DataFile()

    aa = line.split()
    aa = [ x.strip() for x in aa ]
    if len(aa) <2 :
        teeDate(0,"ERROR - action and local filesepc not found in "+line)
        return 2
    action = aa[0]
    if not action in validActions :
        teeDate(0,"ERROR - failed to interpret action: "+action)
        return 2
    localfs = aa[1]


    parents = ""
    if len(aa) >= 3 :
        parents = aa[2]
        if parents != "none" and not os.path.exists(parents) :
            teeDate(0,"ERROR - parents file {} not found for file {} "
                    .format(parents,localfs))
            return 2

    fn = localfs.split("/").pop()
    if fn.count(".") != 5 :
        teeDate(0,"ERROR - name not in 6-field format : " + localfs)
        return 2

    tier = fn.split(".")[0]
    if tier == "log" :
        isLog = True
        # insert the run time into the log file sequencer
        fna = fn.split(".")
        fna[4] = fna[4] + "-" + str(runTime)
        # update the file names
        fn = ".".join(fna)
        dir = os.path.dirname(localfs)
        if dir :
            localfs = dir + "/" + fn
        else :
            localfs = fn

    else :
        isLog = False


    # log files are created, but all others must exist now
    if tier != "log" and not os.path.exists(localfs) :
        teeDate(0,"ERROR - file not found : " + localfs)
        return 2

    acct = fn.split(".")[1]
    if acct == "mu2e" :
        ff = mu2eff[tier]
    else :
        ff = userff[tier]


    if action == "sam" :
        path = ""
        url = ""
        samdisk = ""
    else :
        hs = hashlib.sha256(fn.encode('utf-8')).hexdigest()

        fna = fn.split(".")

        path = ff+"/"+fna[0]+"/"+fna[1]+"/"+fna[2]+"/"+fna[3]+"/"+fna[5]
        path = path+"/"+hs[0:2]+"/"+hs[2:4]
        path = locprefix[action]+"/"+path
        url = "https://fndcadoor.fnal.gov:2880"+path[5:]+"/"+fn
        if action == "tape" :
            samdisk = "enstore"
        else :
            samdisk = "dcache"

    dfile.action = action
    dfile.localfs = localfs
    dfile.fn = fn
    dfile.path = path
    dfile.samdisk = samdisk
    dfile.url = url
    dfile.path = path
    dfile.isLog = isLog
    dfile.parents = parents
    dfile.dosam = True
    if action == "sam" :
        dfile.docopy = False
    else :
        dfile.docopy = True
    dfile.donesam = False
    dfile.donecopy = False
    dfile.samtime = -1
    dfile.copytime = -1
    dfile.samInfo = {}
    dfile.metadata = {}
    dfile.locations = []
    dfile.dcacheInfo = {}

    if verbose > 1 :
        print(dfile)

    dflist.append(dfile)


#/pnfs/mu2e/tape/phy-etc/etc/mu2e/test/000_000/txt/16/14
#/pnfs/mu2e/persistent/datasets/phy-etc/etc/mu2e/test/000_000/txt/16/14
#/pnfs/mu2e/scratch/datasets/phy-etc/etc/mu2e/test/000_000/txt/16/14

#
# return success, deleted or not found, (0), or fail (2)
#
def rmFile(dfile):

    # this is the case if success or fail
    dfile.donecopy = False
    dfile.copytime = -1
    dfile.dcacheinfo = {}

    token = getToken()
    env = {"BEARER_TOKEN" : token}
    cmd = f"gfal-rm -t 300 {dfile.url}"

    for itry, tsleep in enumerate(retries) :
        time.sleep(tsleep)
        result = subprocess.run(cmd, shell=True, timeout=320,
                    encoding="utf-8",capture_output=True, env=env)
        teeDate(1,"Removed {}/{}".format(dfile.path,dfile.fn))

        if result.returncode == 0 :
            return 0
        elif result.returncode == 2 and "MISSING" in result.stdout :
            return 0
        else :
            print("ERROR - rm failed for try {} for {}"\
                  .format(itry,dfile.url))
            print(result.stdout)
            print(result.stderr)

    return 2


#
# return success or record not found (0), or failure (2)
#
def retireSam(dfile):

    rc = 0
    try:
        rec = samweb.retireFile(dfile.fn)
    except samweb_client.exceptions.FileNotFound as e:
        dfile.samtime = -1
    except Exception as e:
        message = str(e)
        teeDate(0,"ERROR - SAM retire file failed for " + \
                dfile.fn + "\nmessage: "+message)
        rc = 2

    dfile.donesam = False
    dfile.samtime = -1

    return rc


#
# return success (0), record not found (1), or failure (2)
#
def getSamMetadata(dfile):

    rec = ""
    try:
        rec = samweb.getMetadataText(dfile.fn, "json", True, False)
    except samweb_client.exceptions.FileNotFound as e:
        dfile.samtime = -1
        return 1
    except Exception as e:
        message = str(e)
        teeDate(0,"ERROR - SAM get metadata failed for " + \
                dfile.fn + "\nmessage: "+message)
        dfile.samtime = -1
        return 2


    dd = json.loads(rec)
    dfile.locations = dd.pop("locations",[])
    dfile.samInfo = dd
    if dfile.samtime != 0 :
        # 0 means this record was written by this process
        # if this process did not write the record, but it is there, record time
        stime = dd["create_date"]
        # take the last colon out of "2023-01-03T01:47:29+00:00" (UTC)
        stime = stime[0:22]+stime[23:]
        # read into a tm struct, tz is ignored
        tt = time.strptime(stime,"%Y-%m-%dT%H:%M:%S%z")
        # convert UTC tm to epoch s
        ftime = calendar.timegm(tt)
        dfile.samtime = ftime


    return 0

#
#
#
def computeCRC(filename):
    buffer_size=2**10*8
    hash0 = 0
    hash1 = 1

    with open(filename, mode="rb") as f:
        chunk = f.read(buffer_size)
        while chunk:
            hash0 = zlib.adler32(chunk,hash0)
            hash1 = zlib.adler32(chunk,hash1)
            chunk = f.read(buffer_size)
    enstore = "{:d}".format(hash0)
    adler32 = "{:x}".format(hash1)
    while len(adler32) < 8 :
        adler32 = "0" + adler32
    return enstore,adler32

#
# returns success (0) , file does not exist (1) or fail (2)
#
def getDcacheInfo(dfile):

    token = getToken()

    dfs = "https://fndcadoor.fnal.gov:3880"
    sloc = "/api/v1/namespace/" + dfile.path[5:] + "/" + dfile.fn + \
           "?checksum=true&locality=true"

    cot = ssl._create_unverified_context()

    conn = http.client.HTTPSConnection("fndcadoor.fnal.gov",
                        port=3880,context=cot)

    header = {"Authorization" : "Bearer "+token }

    conn.request("GET", sloc, headers=header)
    res = conn.getresponse()
    #res = requests.get(url,cert=(cert,cert),verify=vdir,timeout=100)
    if res.status == 404 :
        return 1
    elif res.status != 200 :
        return 2

    # "json" method produces a dict
    dfile.dcacheInfo = json.loads(res.read())
    # this process did not write the output, but it is there
    if dfile.copytime != 0 :
        ftime = int( dfile.dcacheInfo['creationTime'] / 1000 )
        dfile.copytime = ftime


    return 0



##
## returns success (0) , file does not exist (1) or fail (2)
##
#def getDcacheInfo(dfile):
#
#    if 'X509_USER_PROXY' in os.environ :
#        cert = os.environ['X509_USER_PROXY']
#    else :
#        cert = "/tmp/x509up_u"+str(os.getuid())
#
#    if not os.path.exists(cert) :
#        teeDate(0,"ERROR - could not find x509 proxy at "+cert)
#        return 2
#
#    dfs = "https://fndcadoor.fnal.gov:3880/api/v1/namespace/"\
#           + dfile.path[5:] + "/" + dfile.fn
#    url = dfs+"?checksum=true&locality=true"
#    vdir = "/etc/grid-security/certificates"
#
#    try:
#        res = requests.get(url,cert=(cert,cert),verify=vdir,timeout=100)
#        # requests only throws for connection errors
#        # this call causes it to throw for things like file not found
#        res.raise_for_status()
#    except requests.exceptions.HTTPError as e:
#        httpCode = str(e).split()[0]
#        if httpCode == "404" :
#            return 1
#        return 2
#    except Exception as e:
#        return 2
#
#    # "json" method produces a dict
#    dfile.dcacheInfo = res.json()
#    # this process did not write the output, but it is there
#    if dfile.copytime != 0 :
#        ftime = int( dfile.dcacheInfo['creationTime'] / 1000 )
#        dfile.copytime = ftime
#
#
#    return 0


#
# return success (0) or output file exists (1) or fail (2)
#
def copyFile(dfile):

    if failRate > 0. and random.uniform(0.0,4.0) < failRate :
        return 2

    dfile.donecopy = False
    dfile.copytime = -1

    localurl = "file://"+os.path.realpath(dfile.localfs)

    token = getToken()

    env = {"BEARER_TOKEN" : token}
    cmd = "gfal-copy --parent --timeout 1000"
    cmd = cmd + " " + localurl + " " + dfile.url

    rc = 999
    for itry, tsleep in enumerate(retries) :
        time.sleep(tsleep)

        result = subprocess.run(cmd, shell=True, timeout=1100,
                    encoding="utf-8", capture_output=True, env=env)
        rc = result.returncode
        if rc == 0 :
            break
        elif "exists" in result.stderr :
            teeDate(1,"WARNING - output file exists for {}/{}"\
                    .format(dfile.path,dfile.fn))
            return 1
        else :
            teeDate(0,"ERROR - copy failed for try {} for {}".\
                  format(itry,dfile.url))
            print("message: "+message)


    # here, rc might be 0 (success) or not (multiple failures)
    if rc != 0 :
        teeDate(0,"ERROR - retries exhausted, failed to copy "+dfile.url)
        return 2

    # verify copy against dcache checksum
    localCRC = ""
    for crc in dfile.metadata['checksum'] :
        if "adler" in crc :
            localCRC = crc.split(":")[1]

    # set these here so that getDcacheInfo doesn't overwrite time
    dfile.donecopy = True
    dfile.copytime = 0

    rc = getDcacheInfo(dfile)

    if rc != 0 :
        dfile.donecopy = False
        dfile.copytime = -1
        return 2

    remoteCRC = ""
    # array of dicts
    for crcd in dfile.dcacheInfo["checksums"]:
        if crcd['type'] == "ADLER32" :
            remoteCRC = crcd['value']
            break

    if remoteCRC != localCRC or localCRC == "" :
        teeDate(0,"ERROR - dcache CRC does not match local CRC: {} vs {} for".\
                format(localCRC,remoteCRC,dfile.fn))
        dfile.donecopy = False
        dfile.copytime = -1
        return 2

    teeDate(1,"Copied {} to {}".\
                format(dfile.fn,dfile.path))

    return 0



#
# return success (0) or failed (2)
#
def createMetadata(dfile):

    teeDate(1,"Create metadata for "+dfile.fn)

    if failRate > 0.0 and random.uniform(0.0,4.0) < failRate :
        return 2

    ext = dfile.fn.split()[-1]

    cmd = ""
    if dfile.parents == "" or dfile.parents == "none" :
        cmd = cmd+"printJson --no-parents "+dfile.localfs+" 2> err.txt"
    else:
        cmd = cmd+"printJson --parents "+dfile.parents+" "+dfile.localfs


    try:
        jsontext = subprocess.check_output(cmd,shell=True,\
            stderr=subprocess.STDOUT,timeout=600,text=True)
    except Exception as e:
        teeDate(0,"ERROR - printJson failed for "+dfile.fn
                +"\nmessage: "+str(e))
        return 2

    dd = json.loads(jsontext)

    enstore,adler32 = computeCRC(dfile.localfs)
    dd['checksum'] = [ "enstore:"+enstore, "adler32:"+adler32]

    aa = dfile.fn.split(".")
    ds = aa[0:4] + aa[-1:]
    tagt = ".".join(ds) + "_POMS"
    dd['Dataset.Tag'] = tagt

    dd['application'] = { 'family' : appFamily, 'name' : appName, 'version' : appVersion }

    dfile.metadata = dd

    return 0


#
# return success (0) or output file exists (1) or fail (2)
#
def declareSam(dfile):

    teeDate(1,"Declare SAM for "+dfile.fn)

    if failRate > 0.0 and random.uniform(0.0,4.0) < failRate :
        return 2

    dfile.donesam = False
    dfile.samtime = -1

    rc = 999
    for itry, tsleep in enumerate(retries) :
        time.sleep(tsleep)
        try :
            # returns a str with the fileId
            fileId = samweb.declareFile(dfile.metadata)
            dfile.donesam = True
            dfile.samtime = 0
            rc = 0
            break
        except samweb_client.exceptions.FileAlreadyExists as e :
            teeDate(1,"WARNING - Found file already has SAM record: "+dfile.fn)
            return 1
        except Exception as e :
            message = str(e)
            teeDate(0,"ERROR - SAM declare failed for try {} for {}".\
                    format(itry,dfile.fn)+"\nmessage: "+message)
            rc = 2

    if rc == 2 :
        teeDate(0,"ERROR - SAM declare retries exhausted for "+dfile.fn)
        return 2
    elif rc != 0 :
        teeDate(0,"ERROR - SAM declare errors "+str(rc)+" for "+dfile.fn)
        return 2

    # must be ok so far, add location
    loc = dfile.samdisk + ":" + dfile.path

    rc = 0
    for itry, tsleep in enumerate(retries) :
        time.sleep(tsleep)
        try :
            fileId = samweb.addFileLocation(dfile.fn,loc)
            return 0
        except Exception as e :
            message = str(e)
            teeDate(0,"ERROR - SAM ad dlocation failed try {} for {}".\
                    format(itry,dfile.fn)+"\nmessage: "+message)

    teeDate(0,"ERROR - SAM add locations retries exhausted for "+dfile.fn)
    return 2



#
# returns success, all output was either written by this process or
# there is no output, or the previous output was old, ready to recover (0),
# there is a recent output from a previous run (1), or a failure (2)
#

def checkTimes(dfile):

    teeDate(1,"check times for "+dfile.fn)

    if failRate > 0.0 and random.uniform(0.0,4.0) < failRate :
        return 2

    rcfile = 0

    if dfile.donecopy :
        mess = "Found this job wrote file " + dfile.fn
        teeDate(1,mess)
        rcfile = 0

    else :
        rc = getDcacheInfo(dfile)
        if rc == 2 :
            # error other than no file
            return 2

        if rc == 0 :
            # this process did not write the output, but it is there
            deltaTime = runTime - dfile.copytime
            if deltaTime < recoverDelay :
                mess = "Found file {}s old, less than recoverTime for {}".\
                   format(deltaTime,dfile.fn)
                teeDate(1,mess)
                rcfile = 1
            else :
                mess = "Found file {}s old, more than recoverTime for {}".\
                   format(deltaTime,dfile.fn)
                teeDate(1,mess)
                # OK to recover
                rcfile = 0

    rcSAM = 0
    if dfile.donesam :

        mess = "Found this job wrote SAM record for " + dfile.fn
        teeDate(1,mess)
        # SAM record is also OK to recover
        rcSAM = 0

    else :
        rc = getSamMetadata(dfile)

        if rc == 2 :
            # error other than no record
            return 2

        if rc == 0 :
            deltaTime = runTime - dfile.samtime
            if deltaTime < recoverDelay :
                mess = "SAM record is {}s old, less than recoverTime for {}".\
                   format(deltaTime,dfile.fn)
                teeDate(1,mess)
                rcSAM = 1
            else :
                mess = "SAM record is {}s old, more than recoverTime for {}".\
                   format(deltaTime,dfile.fn)
                teeDate(1,mess)
                rcSAM = 0

    # rcFile and rcSAM must be either 0 (we wrote the file/record, 
    # or we did not write it, but it is old, OK to recover) 
    # or 1 (we did not write the the file/record, and it is recent,
    # so not OK to recover yet)
    if rcfile > rcSAM :
        rc = rcfile
    else :
        rc = rcSAM

    return rc

#
# this process is competing to write output,
# delete what we have written so far
#

def rollback(dfile):

    if dfile.donecopy :
        rc = rmFile(dfile)
        if rc == 2 :
            return rc

    if dfile.donesam :
        rc = rmFile(dfile)
        if rc == 2 :
            return rc

    return 0

#
# there are stale files, try to delete them and continue writing
#

def recover(dfile):

    rc = 0

    if not dfile.docopy :
        return 0

    if dfile.donecopy :
        return 0

    rc = rmFile(dfile)
    if rc != 0 : return rc
    rc = retireSam(dfile)
    if rc != 0 : return rc
    if not dfile.metadata :
        rc = createMetadata(dfile)
        if rc != 0 : return rc
    rc = copyFile(dfile)
    if rc != 0 : return rc
    rc = declareSam(dfile)
    if rc != 0 : return rc

    return 0


#
# collect and write log file
#

def writeLog(dfile):

    fn = dfile.fn

    if os.path.exists(fn) :
        os.remove(fn)

#    fout = os.path.expandvars("$HOME/jsb_tmp/JOBSUB_LOG_FILE")
#    ferr = os.path.expandvars("$HOME/jsb_tmp/JOBSUB_ERR_FILE")
    fout = os.path.expandvars("jsb_tmp/JOBSUB_LOG_FILE")
    ferr = os.path.expandvars("jsb_tmp/JOBSUB_ERR_FILE")

    if not os.path.exists(fout) :
        teeDate(0,"ERROR - writeLog could not find " + fout)
        return 2

    with open(fn,"w") as f:
        with open(fout) as jf:
            line = jf.readline()
            while line :
                f.write(line)
                line = jf.readline()
        jf.close()
        f.write("\n")
        f.write("************************* JOBSUB_ERR *********************\n")
        f.write("\n")
        with open(ferr) as jf:
            line = jf.readline()
            while line :
                f.write(line)
                line = jf.readline()

    rc = createMetadata(dfile)
    if rc != 0 :
        return 2
    rc = copyFile(dfile)
    if rc != 0 :
        return 2
    rc = declareSam(dfile)
    if rc != 0 :
        return 2

    return 0
#
#
#

if __name__ == '__main__':
    '''
    main help
    '''


    #
    # globals
    #

    # the list of actions requested in the command file
    dflist = []
    verbose = 1
    retries = [0,10,30]
    runTime = int( time.time() )
    recoverDelay = 3600

    # samweb functions are methods of global objects
    samweb = samweb_client.SAMWebClient()

    # default, normally take app name and verison from MOO_CONFIG
    appDefault = True
    appFamily="Production"
    appName=""
    appVersion=""

    # intentionaly fail at a rate given by MOO_FAIL/100
    failRate = 0.0
    if 'MOO_FAIL' in os.environ :
        failRate = float(os.environ["MOO_FAIL"])/100.0



    parser = argparse.ArgumentParser(description='Copy a set of files to dCache')

    parser.add_argument("filelist", metavar="file_of_files",
                        type=str, help="text file with list of files to transfer")
    parser.add_argument("-v","--verbose", type=int,
                        dest="verbose", default=1,choices=[0, 1, 2],
                        help="int, 0,1,2 for verbosity (default=1)")
    parser.add_argument("-a","--app_default", action="store_const",
                        dest="app_default", default=True, const=None,
                        help="True/False take app name, version from $MOO_CONFIG")

    args = parser.parse_args()

    actionFile = args.filelist
    verbose = args.verbose
    appDefault = args.app_default

    teeDate(1,"start pushOutput")


    if appDefault and 'MOO_CONFIG' in os.environ :
        config = os.environ['MOO_CONFIG']
        appName = config.split("-")[0]
        appVersion = "-".join(config.split("-")[1:])

    if verbose > 0 :
        print("  filelist = ", actionFile)
        print("  verbose = ", verbose)
        print("  appDefault = ", appDefault)
        print("     appName = ", appName)
        print("     appVersion = ", appVersion)


    with open(actionFile) as f:
        line = f.readline()
        while line :
            fillDataFile(line)
            line = f.readline()

    rcWrite = 0
    rcRecover = 0
    rcCheck = 0
    for dfile in dflist :

        #df = DataFile()
        #fillDataFile(df,line)
        #copyFile(df)
        #rmFile(df)
        #getSamMetadata(dfile)
        #createMetadata(df)
        #getDcacheInfo(df)
        #rcWrite = processFile(dfile)
        #if rcWrite != 0 :
        #    break
        #print(df)
        #sys.exit(0)

        # save log file for the end
        if dfile.isLog :
            continue

        createMetadata(dfile)

        # these two can return sucess (0), already exists (1) or fail (2)
        if dfile.docopy:
            rcWrite = copyFile(dfile)
            if rcWrite != 0 :
                break

        if dfile.dosam:
            rcWrite = declareSam(dfile)
            if rcWrite != 0 :
                break


    if rcWrite == 1 :
        # only arrive here if some output already exists
        # go into recovery algorithm
        teeDate(0,"INFO - running checkTimes")
        # check if previous output is recent or stale
        for dfile in dflist :
            if dfile.isLog :
                continue
            rcCheck = checkTimes(dfile)
            if rcCheck != 0 :
                break

        if rcCheck == 1 :
            # recent files from another job exist
            teeDate(0,"INFO - running rollback")
            for dfile in dflist :
                if dfile.isLog :
                    continue
                rcRecover = rollback(dfile)
                if rcRecover == 2 :
                    break
        elif rcCheck == 0 :
            # check found no recent existing files
            teeDate(0,"INFO - running recover")
            for dfile in dflist :
                if dfile.isLog :
                    continue
                rcRecover = recover(dfile)
                if rcRecover == 2 :
                    break

    # initial job rc, before writing log files
    rcJob = 0
    if rcWrite == 0 :
        # normal sucessful write
        rcJob = 0
    elif rcWrite == 1 :
        # found existing output files
        if rcCheck == 0 :
            # result of attempt to overwrite old files
            rcJob = rcRecover
        else :
            # old files were not that old, no overwrite attempted
            # this job must fail, to cause continued recoveries
            rcJob = 3
    else :
        # error during nornmal write attempt
        rcJob = 2


    teeDate(0,"pushOutput status before log write: " + str(rcJob))

    # always try to write the log

    for dfile in dflist :
        if dfile.isLog :
            rc = writeLog(dfile)
            if rc != 0 :
                rcJob = rc

    teeDate(0,"pushOutput status at exit: " + str(rcJob))

    sys.exit(rcJob)
