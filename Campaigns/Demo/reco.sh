#!/bin/bash
#
# run the Pass1 Demo Reco procedure
#

[[ "$MOO_FAIL" && $((RANDOM%400)) -lt $MOO_FAIL ]] && exit 1

RCT=0

source /cvmfs/mu2e.opensciencegrid.org/bin/OfflineOps/functions.sh
RCT=$((RCT+$?))

tee_date "Starting Demo reco.sh"

if [ ! "$OFFLINEOPS_DIR" ]; then
    echo "ERROR - OFFLINEOPS_DIR needs to be defined before this script runs"
    RCT=$((RCT+$?))
fi

if [[ -z "$MOO_CONDITIONS" || "$MOO_CONDITIONS" == "none" ]]; then
    echo "ERROR - MOO_CONDITIONS required but not set: $MOO_CONDITIONS"
    RCT=$((RCT+1))
fi

source /cvmfs/fermilab.opensciencegrid.org/products/common/etc/setups
setup mu2e
muse setup SimJob $MOO_SIMJOB
RCT=$((RCT+$?))

setup -B mu2efiletools
setup -B sam_web_client
setup -B ifdhc

muse status

if [ "$MOO_OUTDIR" == "production" ]; then
    LOCART=tape
    LOCTXT=disk
else
    LOCART=scratch
    LOCTXT=scratch
fi

control_summary exe

get_next_SAM_file
RCT=$((RCT+$?))

if [[ $RCT -eq 0 && -n "$MOO_INPUT" ]]; then

    tee_date "processing $MOO_INPUT"

    BNAME=$(basename $MOO_INPUT)

    DES=$(echo $BNAME | awk -F. '{print $3}' )
    CFG=$(echo $BNAME | awk -F. '{print $4}' )
    SEQ=$(echo $BNAME | awk -F. '{print $5}' )
    LGFN=log.mu2e.${DES}.${MOO_CONFIG}.${SEQ}.log
    RAFN=rec.mu2e.${DES}.${MOO_CONFIG}.${SEQ}.art

    echo "#include \"Production/JobConfig/reco/Reco.fcl\"" > local.fcl
    DBP=$(echo $MOO_CONDITIONS | awk -F: '{print $1}')
    DBV=$(echo $MOO_CONDITIONS | awk -F: '{print $2}')
    DBE=$(echo $MOO_CONDITIONS | awk -F: '{print $3}')
    [ -z "$DBE" ] && DBE=2
    echo "services.DbService.purpose : $DBP" >> local.fcl
    echo "services.DbService.version : $DBV" >> local.fcl
    echo "services.DbService.verbose : $DBE" >> local.fcl


    NEVARG=""
    [ "$MOO_FAKE" == "true" ] && NEVARG="-n 5"

    tee_date "processing $MOO_INPUT"

    mu2e $NEVARG -s $MOO_INPUT -o $RAFN -c local.fcl
    RC=$?

[[ "$MOO_FAIL" && $((RANDOM%400)) -lt $MOO_FAIL ]] && exit 1

    tee_date "done processing, art RC=$RC"

    RCT=$((RCT+RC))

    echo $BNAME > parents.txt

    echo "$LOCART $RAFN  parents.txt" >> output.txt

    if [ $RCT -eq 0 ]; then
        tee_date "Release $MOO_INPUT consumed"
        release_SAM_file consumed
    else
        tee_date "Release $MOO_INPUT skipped"
        release_SAM_file skipped
    fi
fi


if [ $RCT -ne 0 ]; then
    tee_date "removing data files from output list"
    rm output.txt
fi
echo "$LOCTXT $LGFN none" >> output.txt

[[ "$MOO_FAIL" && $((RANDOM%400)) -lt $MOO_FAIL ]] && exit 1

control_summary final

if [ "$MOO_LOCAL" ]; then
    RCP=0
else
    pushOutput output.txt
    RCP=$?
fi

RC=$((RCT+RCP))

tee_date "done Demo/reco.sh RC=$RC"

[[ "$MOO_FAIL" && $((RANDOM%400)) -lt $MOO_FAIL ]] && exit 1

exit $RC
