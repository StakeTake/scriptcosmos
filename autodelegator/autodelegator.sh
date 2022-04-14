#!/bin/bash

while true
do

# Logo

echo "============================================================"
curl -s https://raw.githubusercontent.com/StakeTake/script/main/logo.sh | bash
echo "============================================================"


PS3='Select an action: '
options=(
"Setup parametrs for autodelegator" 
"Start autodelegator"
"Exit")
select opt in "${options[@]}"
               do
                   case $opt in
       
"Setup parametrs for bot")
echo "============================================================"
echo "Setup your wallet name"
echo "============================================================"
read WALLET_NAME
echo export WALLET_NAME=${WALLET_NAME} >> $HOME/.bash_profile

echo "============================================================"
echo "Setup your password"
echo "============================================================"
read PWD
echo export PWD=${PWD} >> $HOME/.bash_profile \
source $HOME/.bash_profile

echo "============================================================"
echo "Setup your DENOM"
echo "============================================================"
read DENOM
echo export DENOM=${DENOM} >> $HOME/.bash_profile \
source $HOME/.bash_profile

echo "============================================================"
echo "Setup your fees"
echo "============================================================"
read FEES
echo export FEES=${FEES} >> $HOME/.bash_profile \
source $HOME/.bash_profile

echo "============================================================"
echo "Setup your chain id"
echo "============================================================"
read CHAIN_ID
echo export CHAIN_ID=${CHAIN_ID} >> $HOME/.bash_profile \
source $HOME/.bash_profile


mkdir $HOME/autodelegate
wget -O $HOME/autodelegator/start.sh https://raw.githubusercontent.com/StakeTake/scriptcosmos/main/autodelegator/start.sh
chmod +x $HOME/autodelegate/start.sh
break
;;
            
"Start bot")
echo "============================================================"
echo "Bot strating"
echo "============================================================"

screen -S AutoDelegate

break
;;

"Exit")
exit
;;

*) echo "invalid option $REPLY";;
esac
done
done