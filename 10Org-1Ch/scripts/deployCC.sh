#!/bin/bash

source scripts/utils.sh

CHANNEL_NAME=${1:-"mychannel"}
CC_NAME=${2}
CC_SRC_PATH=${3}
CC_SRC_LANGUAGE=${4}
CC_VERSION=${5:-"1.0"}
CC_SEQUENCE=${6:-"1"}
CC_INIT_FCN=${7:-"NA"}
CC_END_POLICY=${8:-"NA"}
CC_COLL_CONFIG=${9:-"NA"}
DELAY=${10:-"3"}
MAX_RETRY=${11:-"5"}
VERBOSE=${12:-"false"}

println "executing with the following"
println "- CHANNEL_NAME: ${C_GREEN}${CHANNEL_NAME}${C_RESET}"
println "- CC_NAME: ${C_GREEN}${CC_NAME}${C_RESET}"
println "- CC_SRC_PATH: ${C_GREEN}${CC_SRC_PATH}${C_RESET}"
println "- CC_SRC_LANGUAGE: ${C_GREEN}${CC_SRC_LANGUAGE}${C_RESET}"
println "- CC_VERSION: ${C_GREEN}${CC_VERSION}${C_RESET}"
println "- CC_SEQUENCE: ${C_GREEN}${CC_SEQUENCE}${C_RESET}"
println "- CC_END_POLICY: ${C_GREEN}${CC_END_POLICY}${C_RESET}"
println "- CC_COLL_CONFIG: ${C_GREEN}${CC_COLL_CONFIG}${C_RESET}"
println "- CC_INIT_FCN: ${C_GREEN}${CC_INIT_FCN}${C_RESET}"
println "- DELAY: ${C_GREEN}${DELAY}${C_RESET}"
println "- MAX_RETRY: ${C_GREEN}${MAX_RETRY}${C_RESET}"
println "- VERBOSE: ${C_GREEN}${VERBOSE}${C_RESET}"

FABRIC_CFG_PATH=$PWD/../config/

#User has not provided a name
if [ -z "$CC_NAME" ] || [ "$CC_NAME" = "NA" ]; then
  fatalln "No chaincode name was provided. Valid call example: ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go"

# User has not provided a path
elif [ -z "$CC_SRC_PATH" ] || [ "$CC_SRC_PATH" = "NA" ]; then
  fatalln "No chaincode path was provided. Valid call example: ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go"

# User has not provided a language
elif [ -z "$CC_SRC_LANGUAGE" ] || [ "$CC_SRC_LANGUAGE" = "NA" ]; then
  fatalln "No chaincode language was provided. Valid call example: ./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go"

## Make sure that the path to the chaincode exists
elif [ ! -d "$CC_SRC_PATH" ]; then
  fatalln "Path to chaincode does not exist. Please provide different path."
fi

CC_SRC_LANGUAGE=$(echo "$CC_SRC_LANGUAGE" | tr [:upper:] [:lower:])

# do some language specific preparation to the chaincode before packaging
if [ "$CC_SRC_LANGUAGE" = "go" ]; then
  CC_RUNTIME_LANGUAGE=golang

  infoln "Vendoring Go dependencies at $CC_SRC_PATH"
  pushd $CC_SRC_PATH
  GO111MODULE=on go mod vendor
  popd
  successln "Finished vendoring Go dependencies"

elif [ "$CC_SRC_LANGUAGE" = "java" ]; then
  CC_RUNTIME_LANGUAGE=java

  infoln "Compiling Java code..."
  pushd $CC_SRC_PATH
  ./gradlew installDist
  popd
  successln "Finished compiling Java code"
  CC_SRC_PATH=$CC_SRC_PATH/build/install/$CC_NAME

elif [ "$CC_SRC_LANGUAGE" = "javascript" ]; then
  CC_RUNTIME_LANGUAGE=node

elif [ "$CC_SRC_LANGUAGE" = "typescript" ]; then
  CC_RUNTIME_LANGUAGE=node

  infoln "Compiling TypeScript code into JavaScript..."
  pushd $CC_SRC_PATH
  npm install
  npm run build
  popd
  successln "Finished compiling TypeScript code into JavaScript"

else
  fatalln "The chaincode language ${CC_SRC_LANGUAGE} is not supported by this script. Supported chaincode languages are: go, java, javascript, and typescript"
  exit 1
fi

INIT_REQUIRED="--init-required"
# check if the init fcn should be called
if [ "$CC_INIT_FCN" = "NA" ]; then
  INIT_REQUIRED=""
fi

if [ "$CC_END_POLICY" = "NA" ]; then
  CC_END_POLICY=""
else
  CC_END_POLICY="--signature-policy $CC_END_POLICY"
fi

if [ "$CC_COLL_CONFIG" = "NA" ]; then
  CC_COLL_CONFIG=""
else
  CC_COLL_CONFIG="--collections-config $CC_COLL_CONFIG"
fi

# import utils
. scripts/envVar.sh

packageChaincode() {
  set -x
  peer lifecycle chaincode package ${CC_NAME}.tar.gz --path ${CC_SRC_PATH} --lang ${CC_RUNTIME_LANGUAGE} --label ${CC_NAME}_${CC_VERSION} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode packaging has failed"
  successln "Chaincode is packaged"
}

# installChaincode PEER ORG
installChaincode() {
  ORG=$1
  setGlobals $ORG
  set -x
  peer lifecycle chaincode install ${CC_NAME}.tar.gz >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode installation on peer0.org${ORG} has failed"
  successln "Chaincode is installed on peer0.org${ORG}"
}

# queryInstalled PEER ORG
queryInstalled() {
  ORG=$1
  setGlobals $ORG
  set -x
  peer lifecycle chaincode queryinstalled >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  PACKAGE_ID=$(sed -n "/${CC_NAME}_${CC_VERSION}/{s/^Package ID: //; s/, Label:.*$//; p;}" log.txt)
  verifyResult $res "Query installed on peer0.org${ORG} has failed"
  successln "Query installed successful on peer0.org${ORG} on channel"
}

# approveForMyOrg VERSION PEER ORG
approveForMyOrg() {
  ORG=$1
  setGlobals $ORG
  set -x
  peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA --channelID $CHANNEL_NAME --name ${CC_NAME} --version ${CC_VERSION} --package-id ${PACKAGE_ID} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode definition approved on peer0.org${ORG} on channel '$CHANNEL_NAME' failed"
  successln "Chaincode definition approved on peer0.org${ORG} on channel '$CHANNEL_NAME'"
}

# checkCommitReadiness VERSION PEER ORG
checkCommitReadiness() {
  ORG=$1
  shift 1
  setGlobals $ORG
  infoln "Checking the commit readiness of the chaincode definition on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
  local rc=1
  local COUNTER=1
  # continue to poll
  # we either get a successful response, or reach MAX RETRY
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
    sleep $DELAY
    infoln "Attempting to check the commit readiness of the chaincode definition on peer0.org${ORG}, Retry after $DELAY seconds."
    set -x
    peer lifecycle chaincode checkcommitreadiness --channelID $CHANNEL_NAME --name ${CC_NAME} --version ${CC_VERSION} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} --output json >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    let rc=0
    for var in "$@"; do
      grep "$var" log.txt &>/dev/null || let rc=1
    done
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  if test $rc -eq 0; then
    infoln "Checking the commit readiness of the chaincode definition successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
  else
    fatalln "After $MAX_RETRY attempts, Check commit readiness result on peer0.org${ORG} is INVALID!"
  fi
}

# commitChaincodeDefinition VERSION PEER ORG (PEER ORG)...
commitChaincodeDefinition() {
  parsePeerConnectionParameters $@
  res=$?
  verifyResult $res "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

  # while 'peer chaincode' command can get the orderer endpoint from the
  # peer (if join was successful), let's supply it directly as we know
  # it using the "-o" option
  set -x
  peer lifecycle chaincode commit -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA --channelID $CHANNEL_NAME --name ${CC_NAME} $PEER_CONN_PARMS --version ${CC_VERSION} --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Chaincode definition commit failed on peer0.org${ORG} on channel '$CHANNEL_NAME' failed"
  successln "Chaincode definition committed on channel '$CHANNEL_NAME'"
}

# queryCommitted ORG
queryCommitted() {
  ORG=$1
  setGlobals $ORG
  EXPECTED_RESULT="Version: ${CC_VERSION}, Sequence: ${CC_SEQUENCE}, Endorsement Plugin: escc, Validation Plugin: vscc"
  infoln "Querying chaincode definition on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
  local rc=1
  local COUNTER=1
  # continue to poll
  # we either get a successful response, or reach MAX RETRY
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
    sleep $DELAY
    infoln "Attempting to Query committed status on peer0.org${ORG}, Retry after $DELAY seconds."
    set -x
    peer lifecycle chaincode querycommitted --channelID $CHANNEL_NAME --name ${CC_NAME} >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    test $res -eq 0 && VALUE=$(cat log.txt | grep -o '^Version: '$CC_VERSION', Sequence: [0-9]*, Endorsement Plugin: escc, Validation Plugin: vscc')
    test "$VALUE" = "$EXPECTED_RESULT" && let rc=0
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  if test $rc -eq 0; then
    successln "Query chaincode definition successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
  else
    fatalln "After $MAX_RETRY attempts, Query chaincode definition result on peer0.org${ORG} is INVALID!"
  fi
}

chaincodeInvokeInit() {
  parsePeerConnectionParameters $@
  res=$?
  verifyResult $res "Invoke transaction failed on channel '$CHANNEL_NAME' due to uneven number of peer and org parameters "

  # while 'peer chaincode' command can get the orderer endpoint from the
  # peer (if join was successful), let's supply it directly as we know
  # it using the "-o" option
  set -x
  fcn_call='{"function":"'${CC_INIT_FCN}'","Args":[]}'
  infoln "invoke fcn call:${fcn_call}"
  peer chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA -C $CHANNEL_NAME -n ${CC_NAME} $PEER_CONN_PARMS --isInit -c ${fcn_call} >&log.txt
  res=$?
  { set +x; } 2>/dev/null
  cat log.txt
  verifyResult $res "Invoke execution on $PEERS failed "
  successln "Invoke transaction successful on $PEERS on channel '$CHANNEL_NAME'"
}

chaincodeQuery() {
  ORG=$1
  setGlobals $ORG
  infoln "Querying on peer0.org${ORG} on channel '$CHANNEL_NAME'..."
  local rc=1
  local COUNTER=1
  # continue to poll
  # we either get a successful response, or reach MAX RETRY
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
    sleep $DELAY
    infoln "Attempting to Query peer0.org${ORG}, Retry after $DELAY seconds."
    set -x
    peer chaincode query -C $CHANNEL_NAME -n ${CC_NAME} -c '{"Args":["queryAllCars"]}' >&log.txt
    res=$?
    { set +x; } 2>/dev/null
    let rc=$res
    COUNTER=$(expr $COUNTER + 1)
  done
  cat log.txt
  if test $rc -eq 0; then
    successln "Query successful on peer0.org${ORG} on channel '$CHANNEL_NAME'"
  else
    fatalln "After $MAX_RETRY attempts, Query result on peer0.org${ORG} is INVALID!"
  fi
}

## package the chaincode
packageChaincode

## Install chaincode on peer0.org1 and peer0.org2
infoln "Installing chaincode on peer0.org1..."
installChaincode 1
infoln "Installing chaincode on peer0.org2..."
installChaincode 2
infoln "Installing chaincode on peer0.org3..."
installChaincode 3
infoln "Installing chaincode on peer0.org4..."
installChaincode 4
infoln "Installing chaincode on peer0.org5..."
installChaincode 5
infoln "Installing chaincode on peer0.org6..."
installChaincode 6
infoln "Installing chaincode on peer0.org7..."
installChaincode 7
infoln "Installing chaincode on peer0.org8..."
installChaincode 8
infoln "Installing chaincode on peer0.org9..."
installChaincode 9
infoln "Installing chaincode on peer0.org10..."
installChaincode 10

## query whether the chaincode is installed
queryInstalled 1

## approve the definition for org1
approveForMyOrg 1

## check whether the chaincode definition is ready to be committed
## expect org1 to have approved and org2 not to
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": false" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"


## now approve also for org2
approveForMyOrg 2

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": false" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"

## now approve also for org3
approveForMyOrg 3

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": false" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"

## now approve also for org4
approveForMyOrg 4

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": false" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"

## now approve also for org5
approveForMyOrg 5

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": false" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"

## now approve also for org6
approveForMyOrg 6

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": false" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"

## now approve also for org7
approveForMyOrg 7

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": false" "\"Org9MSP\": false" "\"Org10MSP\": false"

## now approve also for org8
approveForMyOrg 8

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": false" "\"Org10MSP\": false"

## now approve also for org9
approveForMyOrg 9

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": false"

## now approve also for org10
approveForMyOrg 10

## check whether the chaincode definition is ready to be committed
## expect them both to have approved
checkCommitReadiness 1 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 2 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 3 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 4 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 5 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 6 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 7 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 8 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 9 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"
checkCommitReadiness 10 "\"Org1MSP\": true" "\"Org2MSP\": true" "\"Org3MSP\": true" "\"Org4MSP\": true" "\"Org5MSP\": true" "\"Org6MSP\": true" "\"Org7MSP\": true" "\"Org8MSP\": true" "\"Org9MSP\": true" "\"Org10MSP\": true"


## now that we know for sure both orgs have approved, commit the definition
commitChaincodeDefinition 1 2 3 4 5 6 7 8 9 10

## query on both orgs to see that the definition committed successfully
queryCommitted 1
queryCommitted 2
queryCommitted 3
queryCommitted 4
queryCommitted 5
queryCommitted 6
queryCommitted 7
queryCommitted 8
queryCommitted 9
queryCommitted 10

## Invoke the chaincode - this does require that the chaincode have the 'initLedger'
## method defined
if [ "$CC_INIT_FCN" = "NA" ]; then
  infoln "Chaincode initialization is not required"
else
  chaincodeInvokeInit 1 2 3 4 5 6 7 8 9 10
fi

exit 0