#!/bin/bash
#
# script from OfflineOps repo to drive production jobs in POMS
# this script takes all input as enviromentals MOO_*
# - clean ups enviroment that we are called with
# - mv $CONDOR_DIR_INPUT/* .
# - setup mu2e
# - setup OfflineOps (after fetching tarball, if requested)
# - run the job script
#


# define tee_date and save_environment functions
source /cvmfs/mu2e.opensciencegrid.org/bin/OfflineOps/functions.sh

tee_date Starting OfflineOps/wrapper.sh

[ -z "$MOO_VERBOSE" ] && export MOO_VERBOSE=1
node_summary $MOO_VERBOSE

control_summary wrapper

save_environment wrapper_start


#
# fetch the OfflineOps tarball, if needed
#
if [[ "$MOO_SOURCE" =~ "/" ]]; then
    tee_date fetching Offline Ops from $MOO_SOURCE
    source /cvmfs/mu2e.opensciencegrid.org/setupmu2e-art.sh
    setup ifdhc
    LFN=$(basename $MOO_SOURCE)
    ifdh cp --cp_maxretries=1 $MOO_SOURCE $LFN
    tee_date untar OfflineOps source $LFN
    tar -xf $LFN
    rm -f $LFN
    if [ ! -d OfflineOps ]; then
        tee_date Error fetching and utarring Offline Ops tarball
        exit 1
    fi
fi

#
# undo whatever ups exists
#
if [ "$PRODUCTS" ]; then
    tee_date cleaning ups
    TODO=$(ups active | \
        awk '{if($1!="Active" && $1!="ups" && ff==0) {print $1; ff=1;}}' )
    while [ "$TODO" ]
    do
        unsetup $TODO
        TODO=$(ups active | \
            awk '{if($1!="Active" && $1!="ups" && ff==0) {print $1; ff=1;}}' )
    done
    unsetup ups
    unset PRODUCTS
fi

tee_date "mv CONDOR_DIR_INPUT to cwd"
if [ "$CONDOR_DIR_INPUT" ]; then
    /bin/ls -al $CONDOR_DIR_INPUT
    if [ "$(ls $CONDOR_DIR_INPUT)" ]; then
        mv $CONDOR_DIR_INPUT/* .
    fi
fi


tee_date setup OfflineOps $MOO_SOURCE
if [[ "$MOO_SOURCE" =~ "/" ]]; then
    source OfflineOps/Util/setup.sh
else
    setup OfflineOps $MOO_SOURCE
fi

#
# create a config string out of POMS, cfg and input versions
#
export MOO_CAMPAIGN=$POMS4_CAMPAIGN_NAME
export MOO_CAMPAIGN_STAGE=$POMS4_CAMPAIGN_STAGE_NAME
create_config

save_environment wrapper_end

#
# run the executable script
#

tee_date start script $OFFLINEOPS_DIR/Campaigns/$MOO_SCRIPT
$OFFLINEOPS_DIR/Campaigns/$MOO_SCRIPT
RC=$?
tee_date OfflineOps/wrapper exiting with RC=$RC


exit $RC
