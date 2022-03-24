include "../circomlib/circuits/mimc.circom";
include "../circomlib/circuits/eddsamimc.circom";
include "../circomlib/circuits/bitify.circom";
include "./helpers/tx_existence_check.circom";
include "./helpers/balance_existence_check.circom";
include "./helpers/balance_leaf.circom";
include "./helpers/get_merkle_root.circom";
include "./helpers/if_gadgets.circom";

/// @Title  SNARK circuit to proof transactions are done correctly
/// For each transaction, it verifies,
///     transaction check:
///         - transactions existence check: check that transaction exists in the tx_root
///         - transactions signature check: check that transaction is signed by sender
///     sender check:
///         - sender account existence check: check that sender account exists in current_state
///         - balance underflow check: check that sender has sufficient balance to send transaction
///     sender update check:
///         - sender state update: decrement sender balance and increase sender nonce
///         - intermediate root update: update current_state with new sender leaf to get intermediate_root_1
///     receiver check:
///         - receiver account existence check: check that receiver account exists in intermediate_root_1
///     receiver update check:
///         - receiver state update: increment receiver balance
///         - intermediate root update: update intermediate_root_1 with new receiver leaf to get intermediate_root_2
/// Public inputs and output:
/// @param tx_root: Merkle root of a tree of transactions sent to the coordinator
/// @param current_state: Merkle root of old Accounts tree
/// @param out: Merkle root of updated Accounts tree

template Main(n,m) {
// n is depth of balance tree
// m is depth of transactions tree
// for each proof, update 2**m transactions

    // Merkle root of transactions tree
    signal input txRoot;

    // Merkle proof for transaction in tx tree
    signal private input paths2txRoot[2**m, m];

    // binary vector indicating whether node in tx proof is left or right
    signal private input paths2txRootPos[2**m, m];

    // Merkle root of old balance tree
    signal input currentState;

    // intermediate roots (two for each tx), final element is last.
    signal private input intermediateRoots[2**(m+1)+1];

    // Merkle proof for sender account in balance tree
    signal private input paths2rootFrom[2**m, n];

    // binary vector indicating whether node in balance proof for sender account
    // is left or right 
    signal private input paths2rootFromPos[2**m, n];

    // Merkle proof for receiver account in balance tree
    signal private input paths2rootTo[2**m, n];

    // binary vector indicating whether node in balance proof for receiver account
    // is left or right 
    signal private input paths2rootToPos[2**m, n];
    
    // tx info, 10 fields
    signal private input fromX[2**m]; //sender address x coordinate
    signal private input fromY[2**m]; //sender address y coordinate
    signal private input fromIndex[2**m]; //sender account leaf index
    signal private input toX[2**m]; // receiver address x coordinate
    signal private input toY[2**m]; // receiver address y coordinate
    signal private input nonceFrom[2**m]; // sender account nonce
    signal private input amount[2**m]; // amount being transferred
    signal private input tokenTypeFrom[2**m]; // sender token type
    signal private input R8x[2**m]; // sender signature
    signal private input R8y[2**m]; // sender signature
    signal private input S[2**m]; // sender signature

    // additional account info (not included in tx)
    signal private input balanceFrom[2**m]; // sender token balance

    signal private input balanceTo[2**m]; // receiver token balance
    signal private input nonceTo[2**m]; // receiver account nonce
    signal private input tokenTypeTo[2**m]; // receiver token type

    // // new balance tree Merkle root
    signal output out;

    var NONCE_MAX_VALUE = 100;

    // constant zero address
    // Note: there is a special transaction where the receiver is the zero_leaf. 
    //       We consider these to be withdraw transactions and do not change 
    //       the balance and nonce of the zero_leaf.
                         
    var ZERO_ADDRESS_X = 0;
    var ZERO_ADDRESS_Y = 0;

    component txExistence[2**m];
    component senderExistence[2**m];
    component ifBothHighForceEqual[2**m];
    component newSender[2**m];
    component computedRootFromNewSender[2**m];
    component receiverExistence[2**m];
    component newReceiver[2**m];
    component allLow[2**m];
    component ifThenElse[2**m];
    component computedRootFromNewReceiver[2**m];


    currentState === intermediateRoots[0];

    for (var i = 0; i < 2**m; i++) {

        // transactions existence and signature check
        txExistence[i] = TxExistence(m);
        txExistence[i].fromX <== fromX[i];
        txExistence[i].fromY <== fromY[i];
        txExistence[i].fromIndex <== fromIndex[i];
        txExistence[i].toX <== toX[i];
        txExistence[i].toY <== toY[i];
        txExistence[i].nonce <== nonceFrom[i];
        txExistence[i].amount <== amount[i];
        txExistence[i].tokenType <== tokenTypeFrom[i];

        txExistence[i].txRoot <== txRoot;

        for (var j = 0; j < m; j++){
            txExistence[i].paths2rootPos[j] <== paths2txRootPos[i, j] ;
            txExistence[i].paths2root[j] <== paths2txRoot[i, j];
        }

        txExistence[i].R8x <== R8x[i];
        txExistence[i].R8y <== R8y[i];
        txExistence[i].S <== S[i];
    
        // sender existence check
        senderExistence[i] = BalanceExistence(n);
        senderExistence[i].x <== fromX[i];
        senderExistence[i].y <== fromY[i];
        senderExistence[i].balance <== balanceFrom[i];
        senderExistence[i].nonce <== nonceFrom[i];
        senderExistence[i].tokenType <== tokenTypeFrom[i];

        senderExistence[i].balanceRoot <== intermediateRoots[2*i];
        for (var j = 0; j < n; j++){
            senderExistence[i].paths2rootPos[j] <== paths2rootFromPos[i, j];
            senderExistence[i].paths2root[j] <== paths2rootFrom[i, j];
        }
    
        // balance checks
        balanceFrom[i] - amount[i] <= balanceFrom[i];
        balanceTo[i] + amount[i] >= balanceTo[i];

        nonceFrom[i] != NONCE_MAX_VALUE;

        //-----CHECK TOKEN TYPES === IF NON-WITHDRAWS-----//
        ifBothHighForceEqual[i] = IfBothHighForceEqual();
        ifBothHighForceEqual[i].check1 <== toX[i];
        ifBothHighForceEqual[i].check2 <== toY[i];
        ifBothHighForceEqual[i].a <== tokenTypeTo[i];
        ifBothHighForceEqual[i].b <== tokenTypeFrom[i];
        //-----END CHECK TOKEN TYPES-----//  

        // subtract amount from sender balance; increase sender nonce 
        newSender[i] = BalanceLeaf();
        newSender[i].x <== fromX[i];
        newSender[i].y <== fromY[i];
        newSender[i].balance <== balanceFrom[i] - amount[i];
        newSender[i].nonce <== nonceFrom[i] + 1;
        newSender[i].tokenType <== tokenTypeFrom[i];

        // get intermediate root from new sender leaf
        computedRootFromNewSender[i] = GetMerkleRoot(n);
        computedRootFromNewSender[i].leaf <== newSender[i].out;
        for (var j = 0; j < n; j++){
            computedRootFromNewSender[i].paths2root[j] <== paths2rootFrom[i, j];
            computedRootFromNewSender[i].paths2rootPos[j] <== paths2rootFromPos[i, j];
        }

        // check that intermediate root is consistent with input

        computedRootFromNewSender[i].out === intermediateRoots[2*i  + 1];
        //-----END SENDER IN TREE 2 AFTER DEDUCTING CHECK-----//


        // receiver existence check in intermediate root from new sender
        receiverExistence[i] = BalanceExistence(n);
        receiverExistence[i].x <== toX[i];
        receiverExistence[i].y <== toY[i];
        receiverExistence[i].balance <== balanceTo[i];
        receiverExistence[i].nonce <== nonceTo[i];
        receiverExistence[i].tokenType <== tokenTypeTo[i];

        receiverExistence[i].balanceRoot <== intermediateRoots[2*i + 1];
        for (var j = 0; j < n; j++){
            receiverExistence[i].paths2rootPos[j] <== paths2rootToPos[i, j] ;
            receiverExistence[i].paths2root[j] <== paths2rootTo[i, j];
        }

        //-----CHECK RECEIVER IN TREE 3 AFTER INCREMENTING-----//
        newReceiver[i] = BalanceLeaf();
        newReceiver[i].x <== toX[i];
        newReceiver[i].y <== toY[i];

        // if receiver is zero address, do not change balance
        // otherwise add amount to receiver balance
        allLow[i] = AllLow(2);
        allLow[i].in[0] <== toX[i];
        allLow[i].in[1] <== toY[i];

        ifThenElse[i] = IfAThenBElseC();
        ifThenElse[i].aCond <== allLow[i].out;
        ifThenElse[i].bBranch <== balanceTo[i];
        ifThenElse[i].cBranch <== balanceTo[i] + amount[i];  

        newReceiver[i].balance <== ifThenElse[i].out; 
        newReceiver[i].nonce <== nonceTo[i];
        newReceiver[i].tokenType <== tokenTypeTo[i];


        // get intermediate root from new receiver leaf
        computedRootFromNewReceiver[i] = GetMerkleRoot(n);
        computedRootFromNewReceiver[i].leaf <== newReceiver[i].out;
        for (var j = 0; j < n; j++){
            computedRootFromNewReceiver[i].paths2root[j] <== paths2rootTo[i, j];
            computedRootFromNewReceiver[i].paths2rootPos[j] <== paths2rootToPos[i, j];
        }

        // check that intermediate root is consistent with input
        computedRootFromNewReceiver[i].out === intermediateRoots[2*i  + 2];
        //-----END CHECK RECEIVER IN TREE 3 AFTER INCREMENTING-----//
    }
    out <== computedRootFromNewReceiver[2**m - 1].out;


}

component main = Main(4,2);
