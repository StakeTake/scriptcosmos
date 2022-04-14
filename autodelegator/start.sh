#!/bin/bash

source $HOME/.bash_profile
GREEN_COLOR='\033[0;32m'
RED_COLOR='\033[0;31m'
WITHOU_COLOR='\033[0m'
DELEGATOR_ADDRESS=$($PROJECT keys show $WALLETNAME --bech acc -a)
VALIDATOR_ADDRESS=$($PROJECT keys show $WALLETNAME --bech val -a)
DELAY=300 #in secs - how often restart the script

NODE="tcp://localhost:26657" #change it only if you use another rpc port of your node

for (( ;; )); do
        echo -e "Get reward from Delegation"
        echo -e "${PWD}\ny\n" | $PROJECT tx distribution withdraw-rewards ${VALIDATOR_ADDRESS} --chain-id ${CHAIN_ID} --from ${DELEGATOR_ADDRESS} --commission --node ${NODE} --fees ${FEES}${DEMOM} --yes
for (( timer=12; timer>0; timer-- ))
        do
                printf "* sleep for ${RED_COLOR}%02d${WITHOUT_COLOR} sec\r" $timer
                sleep 1
        done
BAL=$($PROJECT q bank balances ${DELEGATOR_ADDRESS} --node ${NODE} -o json | jq -r '.balances | .[].amount')
echo -e "BALANCE: ${GREEN_COLOR}${BAL}${WITHOU_COLOR} $DENOM\n"
        echo -e "Claim rewards\n"
        echo -e "${PWD}\n${PWD}\n" | $PROJECT tx distribution withdraw-all-rewards --from ${DELEGATOR_ADDRESS} --chain-id ${CHAIN_ID} --fees ${FEES}${DENOM} --node ${NODE} --yes
for (( timer=10002; timer>0; timer-- ))
        do
                printf "* sleep for ${RED_COLOR}%02d${WITHOU_COLOR} sec\r" $timer
                sleep 1
        done
BAL=$(${PROJECT} q bank balances ${DELEGATOR_ADDRESS} --output json | jq -r '.balances[] | select(.denom==$DENOM)' | jq -r .amount);
        BAL=$(($BAL- 500))
echo -e "BALANCE: ${GREEN_COLOR}${BAL}${WITHOU_COLOR} ${DENOM}\n"
        echo -e "Stake ALL\n"
if (( BAL > 500 )); then
            echo -e "${PWD}\n${PWD}\n" | $PROJECT tx staking delegate ${VALIDATOR_ADDRESS} ${BAL}${DENOM} --from ${DELEGATOR_ADDRESS} --node ${NODE} --chain-id ${CHAIN_ID} --fees ${FEES}${DENOM} --yes
        else
                                echo -e "BALANCE: ${GREEN_COLOR}${BAL}${WITHOU_COLOR} $DENOM BAL < 0 ((((\n"
        fi
for (( timer=${DELAY}; timer>0; timer-- ))
        do
            printf "* sleep for ${RED_COLOR}%02d${WITHOU_COLOR} sec\r" $timer
            sleep 1
        done
done
