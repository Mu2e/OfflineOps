#
# execute this to make a tarball of this repo and put it on resiliant
#
SCRIPT_DIR=$( dirname "${BASH_SOURCE[0]}" )
TEMP_DIR=$(readlink -f $SCRIPT_DIR/../.. )
cd $TEMP_DIR
TBALL=/pnfs/mu2e/resilient/users/mu2epro/temp/$(date +%s).tgz
tar -czf $TBALL OfflineOps
echo $TBALL
