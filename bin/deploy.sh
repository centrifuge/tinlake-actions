#! /usr/bin/env bash

ACTIONS_BIN_DIR=${ACTIONS_BIN_DIR:-$(cd "${0%/*}"&&pwd)}
cd $ACTIONS_BIN_DIR
# src env for contract deployment
source $ACTIONS_BIN_DIR/util.sh

# create address file and build contracts
cd $ACTIONS_BIN_DIR/../
dapp update && dapp --use solc:0.5.15 build --extract

# create deployment folder
mkdir $ACTIONS_BIN_DIR/../deployments

export ACTIONS=$(seth send --create $ACTIONS_BIN_DIR/../out/Actions.bin 'Actions()')
message Tinlake Actions Address: $ACTIONS

cd $ACTIONS_BIN_DIR
DEPLOYMENT_FILE=$ACTIONS_BIN_DIR/../deployments/addresses_$(seth chain).json

touch $DEPLOYMENT_FILE

addValuesToFile $DEPLOYMENT_FILE <<EOF
{
    "ACTIONS" :"$ACTIONS"
}
EOF

