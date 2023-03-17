#
# source this to use this repo when it is not installed as a UPS product
#
SCRIPT_DIR=$( dirname "${BASH_SOURCE[0]}" )
export OFFLINEOPS_DIR=$(readlink -f $SCRIPT_DIR/.. )
export PATH=$OFFLINEOPS_DIR/bin:$PATH
