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

tee_date Check LANG
printenv | grep LC_
printenv LANG
unset LC_CTYPE

tee_date Check BEARER_TOKEN
if [ "$BEARER_TOKEN" ]; then
    echo "found BEARER_TOKEN set, unsetting it"
    unset BEARER_TOKEN
else
    echo "found BEARER_TOKEN is not set"
fi

# always need to find setup
source /cvmfs/mu2e.opensciencegrid.org/setupmu2e-art.sh


if [ "$MOO_WATCHDOG" ]; then
    tee_date Starting watchdog
    watchdog &
fi

[ -z "$MOO_VERBOSE" ] && export MOO_VERBOSE=1
node_summary $MOO_VERBOSE

control_summary wrapper

save_environment wrapper_start


#
# fetch the OfflineOps tarball, if needed
#
if [[ "$MOO_SOURCE" =~ "/" ]]; then
    tee_date fetching Offline Ops from $MOO_SOURCE
    LFN=$(basename $MOO_SOURCE)
    (
        if ! command -v ifdh >& /dev/null ; then
            muse setup ops
        fi
        ifdh cp --cp_maxretries=1 $MOO_SOURCE $LFN
    )
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
    #unsetup ups
    #unset PRODUCTS
fi

#
# undo whatever spack exists
#
if [ "$SPACK_ROOT" ]; then
    spack unload -a
    unset SPACK_ROOT
    unset SPACK_ENV
    unset SPACK_ENV_VIEW
fi


# allow mu2einit to run again
unset MU2E


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
if [ -n "$POMS4_CAMPAIGN_NAME" ]; then
    export MOO_CAMPAIGN="$POMS4_CAMPAIGN_NAME"
fi
if [ -n "POMS4_CAMPAIGN_STAGE_NAME" ]; then
    export MOO_CAMPAIGN_STAGE=$POMS4_CAMPAIGN_STAGE_NAME
fi

create_config

save_environment wrapper_end

#
# run the executable script
#

tee_date "************ start script $OFFLINEOPS_DIR/Campaigns/$MOO_SCRIPT"
$OFFLINEOPS_DIR/Campaigns/$MOO_SCRIPT
RC=$?
tee_date OfflineOps/wrapper exiting with RC=$RC


exit $RC
