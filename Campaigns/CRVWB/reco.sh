#!/bin/bash
#
# run the Pass1 CRVWB (CRV wideband) teststand Reco procedure
#
# when this runs, offlineops should be setup and $OFFLINEOPS_DIR defined
#


if [ ! "$OFFLINEOPS_DIR" ]; then
    echo "ERROR - OFFLINEOPS_DIR needs to be defined before this script runs"
    exit 1
fi

source /cvmfs/mu2e.opensciencegrid.org/bin/OfflineOps/functions.sh

# fname is the sam project file, set by fife_wrap
tee_date "Starting CRVWB reco.sh"
tee_date "args are: $@"

RCT=0

source /cvmfs/mu2e.opensciencegrid.org/setupmu2e-art.sh
#printenv
muse setup ops
#printenv
# reset to the spack install where this package is
unset SPACK_ENV
unset SPACK_ENV_VIEW
source /cvmfs/mu2e.opensciencegrid.org/spackages/241207/spack/setup-env.sh
spack load $MOO_CRVTESTSTAND

# modify CRV exe control to use local directory
cat $CRVTESTSTAND_DIR/config.txt | \
awk '{
  if(index($1,"crv")==1) {
    print $1" ./"
  } else {
    print $0
  }
}' > config.txt

DATE=$(date +%s)

if [ "$MOO_OUTDIR" == "production" ]; then
    LOCROOT=tape
    LOCTXT=disk
else
    LOCROOT=scratch
    LOCTXT=scratch
fi

control_summary exe

get_next_SAM_file
RCT=$((RCT+$?))

TOPSEQ="000000_00000000"

while [ "$MOO_INPUT" ]
do
    tee_date "processing $MOO_INPUT"

    BNAME=$(basename $MOO_INPUT)
    ifdh cp $MOO_INPUT $BNAME
    RCT=$((RCT+$?))

    DES=$(echo $BNAME | awk -F. '{print $3}' )
    CFG=$(echo $BNAME | awk -F. '{print $4}' )
    SEQ=$(echo $BNAME | awk -F. '{print $5}' )
    if [[ "$SEQ" > "$TOPSEQ" ]]; then
        TOPSEQ=$SEQ
        LGFN=log.mu2e.${DES}.${MOO_CONFIG}.${SEQ}.log
    fi
    CRFN=ntd.mu2e.${DES}.${MOO_CONFIG}.${SEQ}.root
    CPFN=etc.mu2e.${DES}_cali.${MOO_CONFIG}.${SEQ}.pdf
    CTFN=etc.mu2e.${DES}_cali.${MOO_CONFIG}.${SEQ}.txt
    CNFN=ntd.mu2e.${DES}_cali.${MOO_CONFIG}.${SEQ}.root
    RRFN=rec.mu2e.${DES}.${MOO_CONFIG}.${SEQ}.root
    RNFN=rec.mu2e.${DES}-noadc.${MOO_CONFIG}.${SEQ}.root
    RPFN=etc.mu2e.${DES}_reco.${MOO_CONFIG}.${SEQ}.pdf
    RTFN=etc.mu2e.${DES}_reco.${MOO_CONFIG}.${SEQ}.txt
    DQMN=ntd.mu2e.${DES}-DQM.${MOO_CONFIG}-file.${SEQ}.root

    [ $RCT -ne 0 ] && break

    if [ "$MOO_FAKE" ]; then
        date > ntd.mu2e.${DES}.${CFG}.${SEQ}.root
        date > cal.mu2e.${DES}.${CFG}.${SEQ}.pdf
        date > cal.mu2e.${DES}.${CFG}.${SEQ}.txt
        date > cal.mu2e.${DES}.${CFG}.${SEQ}.root
        date > rec.mu2e.${DES}.${CFG}.${SEQ}.root
        date > rec2.mu2e.${DES}.${CFG}.${SEQ}.root
        date > rec.mu2e.${DES}.${CFG}.${SEQ}.pdf
        date > rec.mu2e.${DES}.${CFG}.${SEQ}.txt
        date > dqm.mu2e.${DES}.${CFG}.$SEQ.root
    else

        tee_date "Running parseCrv $SEQ"
        parserCrv $SEQ
        RCT=$((RCT+$?))

        tee_date "Running calibCrv $SEQ"
        calibCrv $SEQ
        RCT=$((RCT+$?))

        FLAG=""
        MAPFILE=""
        FCF=$(echo $BNAME | awk -F. '{print $4}')
        [[ "$FCF" =~ "crvled" ]] && FLAG="-p"
        # if aging config >= 10, add a map file
        if [[ "$FCF" =~ "crvaging" ]]; then
            ADN=$(echo $FCF | awk -F- '{print $2}')
            if [[ "$ADN" > "009" ]]; then
                MAPFILE="$CRVTESTSTAND_DIR/eventdisplay/channelMapCrvAging${ADN}.txt"
                if [ ! -e $MAPFILE ]; then
                    tee_date "Warning - map file expected, but not found: $MAPFILE"
                else
                    FLAG="$FLAG --channelMap $MAPFILE"
                fi
            fi
        fi

        # do not fail if map file not found - check removed on request
        tee_date "Running recoCrv $SEQ $FLAG"
        recoCrv $SEQ $FLAG
        RCT=$((RCT+$?))
    fi

    mv ntd.mu2e.${DES}.${CFG}.${SEQ}.root $CRFN
    mv cal.mu2e.${DES}.${CFG}.${SEQ}.pdf  $CPFN
    mv cal.mu2e.${DES}.${CFG}.${SEQ}.txt  $CTFN
    mv cal.mu2e.${DES}.${CFG}.${SEQ}.root $CNFN
    mv rec.mu2e.${DES}.${CFG}.${SEQ}.root $RRFN
    mv rec2.mu2e.${DES}.${CFG}.${SEQ}.root $RNFN
    mv rec.mu2e.${DES}.${CFG}.${SEQ}.pdf  $RPFN
    mv rec.mu2e.${DES}.${CFG}.${SEQ}.txt  $RTFN
    mv dqm.mu2e.${DES}.${CFG}.$SEQ.root $DQMN

    echo $BNAME > parents_${BNAME}

    echo "$LOCROOT $CRFN  parents_${BNAME}" >> output.txt
    echo "$LOCTXT  $CPFN  parents_${BNAME}" >> output.txt
    echo "$LOCTXT  $CTFN  parents_${BNAME}" >> output.txt
    echo "$LOCTXT  $CNFN  parents_${BNAME}" >> output.txt
    echo "$LOCROOT $RRFN  parents_${BNAME}" >> output.txt
    echo "$LOCROOT $RNFN  parents_${BNAME}" >> output.txt
    echo "$LOCTXT  $RPFN  parents_${BNAME}" >> output.txt
    echo "$LOCTXT  $RTFN  parents_${BNAME}" >> output.txt
    echo "$LOCTXT  $DQMN  parents_${BNAME}" >> output.txt

    if [ $RCT -eq 0 ]; then
        release_SAM_file consumed
        get_next_SAM_file
        RCT=$((RCT+$?))
    else
        release_SAM_file skipped
    fi
done

tee_date "Done file loop, RCT=$RCT"
tee_date "Processed files: $MOO_INPUT_LIST"

if [ $RCT -ne 0 ]; then
    tee_date "processing failed, removing data files from output list"
    rm output.txt
fi
echo "$LOCTXT $LGFN none" >> output.txt

tee_date "Final ls"
ls -l

tee_date "decode token"
httokendecode -H
save_environment final_env_check

if [ "$MOO_LOCAL" ]; then
    RCP=0
else
    pushOutput output.txt
    RCP=$?
fi

RC=$((RCT+RCP))

tee_date "done CRVWB/reco.sh RC=$RC"

exit $RC
