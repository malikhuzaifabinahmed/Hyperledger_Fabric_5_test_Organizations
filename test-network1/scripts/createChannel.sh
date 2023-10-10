#!/bin/bash

# imports  
. scripts/envVar.sh
. scripts/utils.sh

CHANNEL_NAME_1="$1"
CHANNEL_NAME_2="$5"
DELAY="$2"
MAX_RETRY="$3"
VERBOSE="$4"
: ${CHANNEL_NAME_1:="mychannel1"}
: ${CHANNEL_NAME_2:="mychannel2"}
: ${DELAY:="3"}
: ${MAX_RETRY:="5"}
: ${VERBOSE:="false"}

if [ ! -d "channel-artifacts" ]; then
	mkdir channel-artifacts
fi

createChannelTx() {
	set -x
	configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/${CHANNEL_NAME_1}.tx -channelID $CHANNEL_NAME_1
	configtxgen -profile ThreeOrgsChannel -outputCreateChannelTx ./channel-artifacts/${CHANNEL_NAME_2}.tx -channelID $CHANNEL_NAME_2
	res=$?
	{ set +x; } 2>/dev/null
  verifyResult $res "Failed to generate channel configuration transaction..."
}

createChannel() {
	setGlobals 1
	# Poll in case the raft leader is not set yet
	local rc=1
	local COUNTER=1
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
		sleep $DELAY
		set -x
		peer channel create -o localhost:7050 -c $CHANNEL_NAME_1 --ordererTLSHostnameOverride orderer.example.com -f ./channel-artifacts/${CHANNEL_NAME_1}.tx --outputBlock $BLOCKFILE1 --tls --cafile $ORDERER_CA >&log.txt1
		peer channel create -o localhost:7050 -c $CHANNEL_NAME_2 --ordererTLSHostnameOverride orderer.example.com -f ./channel-artifacts/${CHANNEL_NAME_2}.tx --outputBlock $BLOCKFILE2 --tls --cafile $ORDERER_CA >&log.txt2
		res=$?
		{ set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt1
	cat log.txt2
	verifyResult $res "Channel creation failed"
}

# joinChannel ORG
joinChannel1() {
  FABRIC_CFG_PATH=$PWD/../config/
  ORG=$1
  setGlobals $ORG
	local rc=1
	local COUNTER=1
	## Sometimes Join takes time, hence retry
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
    peer channel join -b $BLOCKFILE1 >&log.txt1
    res=$?
    { set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt1
	verifyResult $res "After $MAX_RETRY attempts, peer0.org${ORG} has failed to join channel '$CHANNEL_NAME_1' "
}

joinChannel2() {
  FABRIC_CFG_PATH=$PWD/../config/
  ORG=$1
  setGlobals $ORG
	local rc=1
	local COUNTER=1
	## Sometimes Join takes time, hence retry
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
    peer channel join -b $BLOCKFILE2 >&log.txt2
    res=$?
    { set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt2
	verifyResult $res "After $MAX_RETRY attempts, peer0.org${ORG} has failed to join channel '$CHANNEL_NAME_2' "
}

setAnchorPeer1() {
  ORG=$1
  docker exec cli ./scripts/setAnchorPeer.sh $ORG $CHANNEL_NAME_1 
}

setAnchorPeer2() {
  ORG=$3
  docker exec cli ./scripts/setAnchorPeer.sh $ORG $CHANNEL_NAME_2 
}

FABRIC_CFG_PATH=${PWD}/configtx

## Create channeltx
infoln "Generating channel create transactions '${CHANNEL_NAME_1}.tx' and '${CHANNEL_NAME_2}.tx'"
createChannelTx

FABRIC_CFG_PATH=$PWD/../config/
BLOCKFILE1="./channel-artifacts/${CHANNEL_NAME_1}.block"
BLOCKFILE2="./channel-artifacts/${CHANNEL_NAME_2}.block"

## Create channel
infoln "Creating channels ${CHANNEL_NAME_1} and ${CHANNEL_NAME_2}"
createChannel
successln "Channels '$CHANNEL_NAME_1' and '$CHANNEL_NAME_2' created"

## Join all the peers to the channel
infoln "Joining org1 peer to the channel1..."
joinChannel1 1
infoln "Joining org2 peer to the channel1..."
joinChannel1 2
infoln "Joining org3 peer to the channel1..."
joinChannel1 3
infoln "Joining org4 peer to the channel1..."
joinChannel1 4
infoln "Joining org5 peer to the channel1..."
joinChannel1 5

infoln "Joining org3 peer to the channel2..."
joinChannel2 3
infoln "Joining org4 peer to the channel2..."
joinChannel2 4
infoln "Joining org5 peer to the channel2..."
joinChannel2 5


## Set the anchor peers for each org in the channel
infoln "Setting anchor peer for org1 in channel1..."
setAnchorPeer1 1
infoln "Setting anchor peer for org2 in channel1..."
setAnchorPeer1 2
infoln "Setting anchor peer for org3 in channel1..."
setAnchorPeer1 3
infoln "Setting anchor peer for org4 in channel1..."
setAnchorPeer1 4
infoln "Setting anchor peer for org5 in channel1..."
setAnchorPeer1 5

successln "Channel '$CHANNEL_NAME_1' joined"

infoln "Setting anchor peer for org3 in channel2..."
setAnchorPeer2 3
infoln "Setting anchor peer for org4 in channel2..."
setAnchorPeer2 4
infoln "Setting anchor peer for org5 in channel2..."
setAnchorPeer2 5


successln "Channel '$CHANNEL_NAME_2' joined"
