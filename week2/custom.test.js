const hre = require('hardhat')
const { ethers, waffle } = hre
const { loadFixture } = waffle
const { expect } = require('chai')
const { utils } = ethers

const Utxo = require('../src/utxo')
const { transaction, registerAndTransact, prepareTransaction, buildMerkleTree } = require('../src/index')
const { toFixedHex, poseidonHash } = require('../src/utils')
const { Keypair } = require('../src/keypair')
const { encodeDataForBridge } = require('./utils')

const MERKLE_TREE_HEIGHT = 5
const l1ChainId = 1
const MINIMUM_WITHDRAWAL_AMOUNT = utils.parseEther(process.env.MINIMUM_WITHDRAWAL_AMOUNT || '0.05')
const MAXIMUM_DEPOSIT_AMOUNT = utils.parseEther(process.env.MAXIMUM_DEPOSIT_AMOUNT || '1')

describe('CustomTest', function () {
    this.timeout(20000)

    async function deploy(contractName, ...args) {
        const Factory = await ethers.getContractFactory(contractName)
        const instance = await Factory.deploy(...args)
        return instance.deployed()
    }

    async function fixture() {
        require('../scripts/compileHasher')
        const [sender, gov, l1Unwrapper, multisig] = await ethers.getSigners()
        const verifier2 = await deploy('Verifier2')
        const verifier16 = await deploy('Verifier16')
        const hasher = await deploy('Hasher')

        const token = await deploy('PermittableToken', 'Wrapped ETH', 'WETH', 18, l1ChainId)
        await token.mint(sender.address, utils.parseEther('10000'))

        const amb = await deploy('MockAMB', gov.address, l1ChainId)
        const omniBridge = await deploy('MockOmniBridge', amb.address)

        const merkleTreeWithHistory = await deploy(
            'MerkleTreeWithHistoryMock',
            MERKLE_TREE_HEIGHT,
            hasher.address,
          )
        await merkleTreeWithHistory.initialize()

        /** @type {TornadoPool} */
        const tornadoPoolImpl = await deploy(
            'TornadoPool',
            verifier2.address,
            verifier16.address,
            MERKLE_TREE_HEIGHT,
            hasher.address,
            token.address,
            omniBridge.address,
            l1Unwrapper.address,
            gov.address,
            l1ChainId,
            multisig.address,
        )
        
        const { data } = await tornadoPoolImpl.populateTransaction.initialize(
            MINIMUM_WITHDRAWAL_AMOUNT,
            MAXIMUM_DEPOSIT_AMOUNT,
        )
        const proxy = await deploy(
            'CrossChainUpgradeableProxy',
            tornadoPoolImpl.address,
            gov.address,
            data,
            amb.address,
            l1ChainId,
        )

        const tornadoPool = tornadoPoolImpl.attach(proxy.address)

        await token.approve(tornadoPool.address, utils.parseEther('10000'))

        return { merkleTreeWithHistory, tornadoPool, token, omniBridge }
    }

    it('should insert, deposit from L1 and withdraw in L2', async () => {
        // estimate and print gas needed to insert a pair of leaves to MerkleTreeWithHistory 
        const { merkleTreeWithHistory, tornadoPool, token, omniBridge } = await loadFixture(fixture);
        const gas = await merkleTreeWithHistory.estimateGas.insert(toFixedHex(123), toFixedHex(456));
        console.log("MerkleTreeWithHistory insert gas:", gas.toNumber());

        // Alice deposits 0.08 ETH into tornado pool from L1
        const aliceKeypair = new Keypair() 
        
        const aliceDepositAmount = utils.parseEther('0.08')
        const aliceDepositUtxo = new Utxo({ amount: aliceDepositAmount, keypair: aliceKeypair })
        const { args, extData } = await prepareTransaction({
          tornadoPool,
          outputs: [aliceDepositUtxo],
        })
    
        const onTokenBridgedData = encodeDataForBridge({
          proof: args,
          extData,
        })
    
        const onTokenBridgedTx = await tornadoPool.populateTransaction.onTokenBridged(
          token.address,
          aliceDepositUtxo.amount,
          onTokenBridgedData,
        )
        // emulating bridge. first it sends tokens to omnibridge mock then it sends to the pool
        await token.transfer(omniBridge.address, aliceDepositAmount)
        const transferTx = await token.populateTransaction.transfer(tornadoPool.address, aliceDepositAmount)
    
        await omniBridge.execute([
          { who: token.address, callData: transferTx.data }, // send tokens to pool
          { who: tornadoPool.address, callData: onTokenBridgedTx.data }, // call onTokenBridgedTx
        ])

        // Alice withdraws 0.05 ETH from the shielded pool to a recipient in L2
        const aliceWithdrawAmount = utils.parseEther('0.05')
        const recipient = '0xDeaD00000000000000000000000000000000BEEf'
        const aliceChangeUtxo = new Utxo({
        amount: aliceDepositAmount.sub(aliceWithdrawAmount),
        keypair: aliceKeypair,
        })
        await transaction({
            tornadoPool,
            inputs: [aliceDepositUtxo],
            outputs: [aliceChangeUtxo],
            recipient: recipient,
        })

        // recipient balance should be 0.05 eth
        const recipientBalance = await token.balanceOf(recipient)
        expect(recipientBalance).to.be.equal(aliceWithdrawAmount)
        // omnibridge balance should be 0
        const omniBridgeBalance = await token.balanceOf(omniBridge.address)        
        expect(omniBridgeBalance).to.be.equal(0)
        //tornado pool balance should be 0.03
        const tornadoPoolBalance = await token.balanceOf(tornadoPool.address)
        expect(tornadoPoolBalance).to.be.equal(aliceDepositAmount.sub(aliceWithdrawAmount))
    })
})
