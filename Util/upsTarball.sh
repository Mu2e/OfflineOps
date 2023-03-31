#!/bin/bash
#
# script to make a ups tarball
# args: $1=version
# the content of the tarball will be whatever is in this script's directory
# tarball will be created in the cwd
#
VERSION="$1"
if [ ! "$VERSION" ]; then
    echo "ERROR - no required version argument"
    exit 1
fi

OWD=$PWD

echo ${BASH_SOURCE}
SDIR=$(readlink -f $(dirname ${BASH_SOURCE} )/.. )

PDIR=$(mktemp -d)
cd $PDIR

mkdir -p OfflineOps
cd OfflineOps
mkdir -p $VERSION
cd $VERSION

rsync --exclude "*~" --exclude "*__*"  \
    -r $SDIR/bin $SDIR/Campaigns $SDIR/Util  .
mkdir -p ups
cd ups

cat > OfflineOps.table <<EOL
File    = table
Product = OfflineOps

#*************************************************
# Starting Group definition

Group:

Flavor     = ANY
  Action = flavorSetup


Common:
  Action = setup
    setupRequired( ifdhc  )
    setupRequired( sam_web_client  )
    prodDir()
    setupEnv()
    envSet(\${UPS_PROD_NAME_UC}_VERSION, $VERSION)
    pathPrepend(PATH,\${UPS_PROD_DIR}/bin)
    #pathPrepend(PYTHONPATH,\${UPS_PROD_DIR}/python)
    exeActionRequired(flavorSetup)

End:
# End Group definition
#*************************************************
EOL

# up to OfflineOps dir
cd ../..

mkdir -p ${VERSION}.version
cd ${VERSION}.version

cat > NULL <<EOL
FILE = version
PRODUCT = OfflineOps
VERSION = $VERSION

FLAVOR = NULL
QUALIFIERS = ""
  PROD_DIR = OfflineOps/$VERSION
  UPS_DIR = ups
  TABLE_FILE = OfflineOps.table

EOL

cd ../..

tar -cjf $OWD/OfflineOps-${VERSION}.bz2 OfflineOps/${VERSION} OfflineOps/${VERSION}.version
rm -rf $PDIR/OfflineOps
rmdir $PDIR

cd $OWD
exit 0
