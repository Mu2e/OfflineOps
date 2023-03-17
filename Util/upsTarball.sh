#!/bin/bash
#
# script to make a ups tarball
# args: $1=version
# tarball will be created in the cwd
#
VERSION="$1"
if [ ! "$VERSION" ]; then
    echo "ERROR - no required version argument"
    exit 1
fi

OWD=$PWD
SDIR=$(dirname $(readlink -f $BASH_SOURCE)  | sed 's|/build||' )

PDIR=$(mktemp -d)
cd $PDIR

mkdir -p OfflineOps
cd OfflineOps
mkdir -p $VERSION
cd $VERSION

rsync --exclude "*~" --exclude "*__*"  \
    -r $SDIR/bin $SDIR/Campaigns $SIDR/Util  .
mkdir -p ups
cd ups

cat > dhtools.table <<EOL
File    = table
Product = OfflineOps

#*************************************************
# Starting Group definition

Group:

Flavor     = ANY

Common:
  Action = setup
    setupRequired( ifdhc  )
    setupRequired( sam_web_client  )
    prodDir()
    setupEnv()
    envSet(\${UPS_PROD_NAME_UC}_VERSION, $VERSION)
    sourceRequired(\${UPS_PROD_DIR}/bin/dh_functions.sh,UPS_ENV)
    pathPrepend(PATH,\${UPS_PROD_DIR}/bin)
    pathPrepend(PYTHONPATH,\${UPS_PROD_DIR}/python)
    exeActionRequired(flavorSetup)

End:
# End Group definition
#*************************************************
EOL

# up to dhtools dir
cd ../..

mkdir -p ${VERSION}.version
cd ${VERSION}.version

cat > NULL <<EOL
FILE = version
PRODUCT = dhtools
VERSION = $VERSION

FLAVOR = NULL
QUALIFIERS = ""
  PROD_DIR = dhtools/$VERSION
  UPS_DIR = ups
  TABLE_FILE = dhtools.table

FLAVOR = NULL
QUALIFIERS = "grid"
  PROD_DIR = dhtools/$VERSION
  UPS_DIR = ups
  TABLE_FILE = dhtools.table
EOL

cd ../..

tar -cjf $OWD/dhtools-${VERSION}.bz2 dhtools/${VERSION} dhtools/${VERSION}.version
rm -rf $PDIR/dhtools
rmdir $PDIR

cd $OWD
exit 0
