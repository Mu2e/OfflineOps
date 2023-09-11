#
# some utitity functions for production grid jobs
# from OfflineOps repo
#

#
# write a message to both log and err log
#
tee_date() {
echo "[$(date)] $*"
[ ! -t 2 ] && echo "[$(date)] $*" 1>&2
}

#
# echo a few useful data for this node
# if $1 = 1 or 2 then more verbose
#
node_summary() {
    local VERBOSE="1"
    [ "$1" ] && VERBOSE="$1"
    [ $VERBOSE -eq 0 ] && return 0
    echo "************** host summary ***************"
    echo "host: $(hostname)"
    echo "n_processors: $(cat /proc/cpuinfo | grep -c processor)"
    local ARCH=$(cat /proc/cpuinfo | grep "model name" | head -1 | sed 's/^.*://')
    echo "arch: $ARCH"
    echo "bogomips: $(cat /proc/cpuinfo | grep bogomips | head -1 | awk '{print $NF}')"
    echo "uname: $(uname -a)"
    if command -v lsb_release > /dev/null 2>&1 ; then
        lsb_release -a | sed 's/^/   /'
    elif [ -e /etc/redhat-release ]; then
        echo "/etc/redhat-release: $(cat /etc/redhat-release)"
    else
        echo "could not find linux name"
    fi
    echo "SINGULARITY_NAME: $SINGULARITY_NAME"

    echo "GLIDEIN_Site: $GLIDEIN_Site"

    /bin/ls /cvmfs/fermilab.opensciencegrid.org > /dev/null  2>&1
    RC=$?
    /bin/ls /cvmfs/mu2e.opensciencegrid.org > /dev/null  2>&1
    RC=$((RC+$?))
    if [ $RC -eq 0 ]; then
        echo "cvmfs: OK"
    else
        echo "cvmfs: ERROR on simple ls"
    fi

    if [[ $RC -ne 0 || $VERBOSE -gt 0 ]]; then
        if command -v  cvmfs_config ; then
            cvmfs_config stat -v fermilab.opensciencegrid.org
            cvmfs_config stat -v mu2e.opensciencegrid.org
        fi
    fi

    if [ "$(rpm -q -a | grep zstd)" ]; then
        echo "rpm_check: has art 3.6 rpms"
    else
        echo "rpm_check: ERROR - does not have art 3.6 rpms"
    fi

    echo "GRID_USER: $GRID_USER"
    echo "whoami: $(whoami)"

    if command -v klist > /dev/null 2>&1 ; then
        klist -s > /dev/null 2>&1
        RC=$?
        if [ $RC -eq 0 ] ; then
            echo "kerberos: OK"
        else
            echo "kerberos: NOT OK"
        fi
        # kerberos not expected on a grid node
        if [[ ( $RC -ne 0 && ! "$GRID_USER" ) || VERBOSE -gt 0 ]]; then
            klist
        fi
    else
        echo "kerberos: could not find Klist"
    fi
    printenv | grep KRB5

    if command -v voms-proxy-info > /dev/null 2>&1 ; then
        voms-proxy-info -exists > /dev/null 2>&1
        RC=$?
        if [ $RC -eq 0 ] ; then
            echo "voms proxy: OK"
        else
            echo "voms proxy: NOT OK"
        fi
        if [[ $RC -ne 0 || VERBOSE -gt 0 ]]; then
            voms-proxy-info
        fi
    else
        echo "voms proxy: could not find voms-proxy-info"
    fi
    printenv | grep X509

    if command -v httokendecode > /dev/null 2>&1 ; then
        httokendecode > /dev/null 2>&1
        RC=$?
        if [ $RC -eq 0 ]; then
            echo "token: OK"
        else
            echo "token: NOT OK"
        fi
        if [[ $RC -ne 0 || VERBOSE -gt 0 ]]; then
            httokendecode
        fi
    else
        echo "token: could not find httokendecode"
    fi
    printenv | grep TOKEN

    echo "pwd: $PWD"

    if [ $VERBOSE -gt 0 ]; then
        if [ $VERBOSE -gt 1 ]; then
            echo "df on system:"
            df -h
        else
            echo "df on system (skipping cvmfs partitions):"
            df -h | grep -v cvmfs
        fi

        echo "ulimit:"
        ulimit -a

        echo "glibc rpm:"
        rpm -q -a | grep glibc
    fi

    if [ $VERBOSE -gt 1 ]; then
        echo "glibc executed:"
        /lib64/libc.so.6
        echo "glibc grepped:"
        strings /lib64/libc.so.6 | grep GLIBC
        echo "job ad:"
        [ -e .job.ad ] && cat .job.ad
        echo "jsb_tmp/ifdh.sh"
        [ -e jsb_tmp/ifdh.sh ] && cat jsb_tmp/ifdh.sh
        echo "rpms:"
        rpm -q -a
        echo "typeset:"
        typeset
    fi


    echo "************** host summary ***************"
}


#
# echo control environmentals
# $1 = an optional label
#
control_summary() {
    echo "************** control summary $1 ***************"
    for LL in $(printenv)
    do
        if [ "$(echo $LL | cut -c 1-4)" == "MOO_" ]; then
            echo $LL
        fi
    done
    echo "************** control summary $1 ***************"
}

#
# save env and ups active to stderr
# $1 = a one-word label
#
save_environment() {
    local LABEL="$1"
    [ -z "$LABEL" ] && LABEL="unlabeled"

    (
        echo
        echo "************************* $LABEL ************************** "
        echo
        printenv
        echo "********* pwd"
        pwd
        if command -v ups 2>&1 > /dev/null ; then
            echo "********* ups active"
            ups active
        fi
        echo "********* ls"
        /bin/ls -al
        echo "********* ls of \*"
        /bin/ls -al *
    ) 1>&2

}

#
# take environmentals MOO_CAMPAIGN, MOO_CFGNAME and MOO_CFGVERSION,
# check that they are consistent, and create a new MOO_CONFIG
# which is the config field for output files
#
create_config() {
    export MOO_CONFIG="error"
    # expecting campaign name_xyz-000-0
    local PN=$(echo $MOO_CAMPAIGN | awk -F- '{print $1}' )
    local PV=$(echo $MOO_CAMPAIGN | awk -F- '{print $2}' )
    local CN=$(echo $MOO_CFG | awk -F- '{print $1}')
    local CV=$(echo $MOO_CFG | awk -F- '{print $2}')
    local IN=$(echo $MOO_DATASET | awk -F- '{print $1}')
    local IV=$(echo $MOO_DATASET | awk -F- '{print $2}')

    if [ "$CN" != "$PN" ]; then
        echo "ERROR - cfg name $CN does not agree with campaign name ($PN)"
        return 1
    fi
    if [ "$IN" != "$PN" ]; then
        echo "ERROR - dataset name $IN does not agree with campaign name ($PN)"
        return 1
    fi
    local APPEND_NAME=""
    [ "$MOO_APPEND_NAME" != "none" ] && APPEND_NAME=$MOO_APPEND_NAME
    export MOO_CONFIG=${PN}-${PV}-${CV}-${IV}${APPEND_NAME:+_$APPEND_NAME}
    return 0
}


#
# function to look at environmental variables to find a running consumer,
# then ask for the next files from that project.  Intended to be used
# in a POMS job running inside a SAM project.
# Returns the file by setting
# MOO_INPUT and add the file to a list at MOO_INPUTS
#
get_next_SAM_file() {

    [ $MOO_VERBOSE -ge 1 ] && tee_date "starting get-next-file"

    [ $MOO_VERBOSE -ge 2 ] && printenv | grep SAM

    export MOO_INPUT=""

    if [ -n "$MOO_LOCAL_INPUT" ]; then
        export MOO_INPUT=""

        for FN in $(echo $MOO_LOCAL_INPUT | tr "," " " )
        do
            if [[ ! "$MOO_INPUT_LIST" =~ "$FN" ]]; then
                export MOO_INPUT="$FN"
                export MOO_INPUT_LIST=${MOO_INPUT_LIST:+$MOO_INPUT_LIST,}$MOO_INPUT
                break
            fi
        done

        return 0
    fi

    if ! command -v samweb > /dev/null 2>&1 ; then
        tee_date "ERROR - get_next_SAM_file called without samweb available"
        return 1
    fi
    if [[ -z "$SAM_PROJECT" || -z "$SAM_CONSUMER_ID" ]]; then
        tee_date "ERROR - get_next_SAM_file called without SAM consumer environmentals"
        return 1
    fi

    local TMPS=$(mktemp)
    local TMPE=$(mktemp)

    samweb get-next-file $SAM_PROJECT $SAM_CONSUMER_ID 1>$TMPS 2>$TMPE
    local TT=$?

    local STDO=$(cat $TMPS)
    local STDE=$(cat $TMPE)
    rm -f $TMPS $TMPE

    # if command timeout, TT=0 but output contains Traceback
    local RC=0
    if [ $TT -eq 0 ]; then
        if [[ "$STDE" =~ "Traceback" ]]; then
            # case of final timeout
            RC=1
        else
            # case of a file delivered
            # case of no more files (STDO="")
            RC=0
        fi
    else
        RC=1
    fi

    if [[ $MOO_VERBOSE -ge 2 || $RC -ne 0 || -n "$STDE" ]]; then
        echo "[$(date)] get-next-file returned:"
        echo "stdout=$STDO"
        echo "stderr=$STDE"
        echo "command rc=$TT"
    fi

    if [ $RC -eq 0 ]; then
        # blank STDO might just mean end of input files
        export MOO_INPUT="$STDO"
        if [ -n "$MOO_INPUT" ]; then
            export MOO_INPUT_LIST=${MOO_INPUT_LIST:+$MOO_INPUT_LIST,}$MOO_INPUT
        fi
    fi

    [ $MOO_VERBOSE -ge 1 ] && tee_date "returning get-next-file RC=$RC MOO_INPUT=$MOO_INPUT"

    return $RC

}

#
# release the file in MOO_INPUT
# if there is an argument, it should be "consumed"
# for sucess or "skipped" if the file was not processed
# if no argument, assume consumed
#
release_SAM_file() {

    if [ -n "$MOO_LOCAL_INPUT" ]; then
        unset MOO_INPUT
        return 0
    fi

    if ! command -v samweb > /dev/null 2>&1 ; then
        echo "ERROR - release_SAM_file called without samweb available"
        return 1
    fi
    if [[ -z "$SAM_PROJECT" || -z "$SAM_CONSUMER_ID" ]]; then
        echo "ERROR - release_SAM_file called without SAM consumer environmentals"
        return 1
    fi
    if [ -z "$MOO_INPUT" ]; then
        echo "ERROR - release_SAM_file called with MOO_INPUT unset"
        return 1
    fi
    local STATUS="$1"
    [ -z "$STATUS" ] && STATUS=consumed
    if [[ "$STATUS" != "consumed" && "$STATUS" != "skipped" ]]; then
        echo "ERROR - release_SAM_file called bad argument: $STATUS"
        return 1
    fi
    samweb set-process-file-status $SAM_PROJECT $SAM_CONSUMER_ID $MOO_INPUT $STATUS
    local TT=$?
    unset MOO_INPUT

    return $TT

}


# function for capturing what is happening
# during a job, for cases when the job will
# go to hold
#
# in the startof the main script:
# source this file
# watchdog <TIME> &
# TIME is optional (default to 7200) seconds after which the watchdog exits
#
# $1 = optional time limit in s
# outdir assumed: /pnfs/mu2e/scratch/users/$GRID_USER/watchdog
# ifdh assumed setup

watchdog() {

    local TL=$1
    [ -z "$TL" ] && TL=7200

    local ULOC="mu2e"
    if [ "$GRID_USER" ]; then
        ULOC="$GRID_USER"
    elif [ "$USER" ]; then
        ULOC="$USER"
    fi

    DD=/pnfs/mu2e/scratch/users/$ULOC/watchdog

    [ -z "$MU2E" ] && source /cvmfs/mu2e.opensciencegrid.org/setupmu2e-art.sh
    [ -z "$SETUP_IFDHC" ] && setup ifdhc

    ifdh mkdir_p $DD

    local T0=$( date +%s )
    local DT=0
    local FN="watchdog"
    local PP=$( printf "%09d_%04d" $CLUSTER $PROCESS )
    while [ $DT -lt $TL ];
    do
        sleep 600

        FN=watchdog.${PP}_$(date +%Y_%m_%d-%H_%M)

        echo "************************************************* ps" >> $FN
        ps -fwww f >> $FN
        echo "************************************************* top" >> $FN
        top -n 1 -b >> $FN
        echo "************************************************* ls" >> $FN
        ls -l >> $FN
        echo "************************************************* OUT log" >> $FN
        cat jsb_tmp/JOBSUB_LOG_FILE >> $FN
        echo "************************************************* ERR log" >> $FN
        cat jsb_tmp/JOBSUB_ERR_FILE >> $FN

        ifdh cp $FN $DD/$FN

        DT=$(( $( date +%s ) - $T0 ))
    done
    echo "watchdog exiting on time limit $TL"


}

# so watchdog can be run in a subshell
export -f watchdog
