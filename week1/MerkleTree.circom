pragma circom 2.0.0;

include "mimcsponge.circom";

/// implements MarkleTree using MiMCsponge hash function
template MerkleTree(nLeaves){
    signal input leaves[nLeaves];
    signal output rootHash;

    // Calculate how much hash nodes are required
    var nNodes = nLeaves * 2 - 1;
    component mimc[nNodes];

    // Calculate hash for all leaves
    for (var i = 0; i < nLeaves; i++){
        mimc[i] = MiMCSponge(1, 220, 1);
        mimc[i].ins[0] <== leaves[i];
        mimc[i].k <== 0;
    }

    // Build Merkle hash tree on 
    // Number of hash needed to build on children nodes/leaves
    var nHash = nLeaves / 2;
    // mimc Array index points to the start of the children 
    var iStart = 0;
    // mimc Array index to store the newly built parent
    var iIndex = nLeaves;
    while (iIndex < nNodes) {
        for (var i = 0; i < nHash; i++){
            mimc[iIndex] = MiMCSponge(2, 220, 1);
            mimc[iIndex].ins[0] <== mimc[iStart].outs[0];
            mimc[iIndex].ins[1] <== mimc[iStart + 1].outs[0];
            mimc[iIndex].k <== 0;

            iStart += 2;
            iIndex++;
        }

        nHash /= 2;
    }

    rootHash <== mimc[nNodes - 1].outs[0];
}

component main = MerkleTree(8);
