![](https://i.yapx.ru/RTuEU.jpg)

___In this guide, we have written how to set up an autodelegator for your validator node. The guide is suitable for any project of the cosmos network___

We need to do is set the variables correctly

1. The name of the project corresponds to the node startup service file
__Project example - umeed__

2. The name of the wallet that you wrote when installing the node
3. The password is set according to your password from the created wallet
4. The validator address and the delegator address will be set automatically, the only thing you need to do is enter the wallet password when setting the variable
5. You can find out the DENOM variable when requesting the balance of tokens on your wallet, this will be the name of the coins
6. The FEES variable is usually set to 0, but depends on the network
7. CHAIN ​​ID is usually set by the name of the testnet or mainnet
Example - umee-1