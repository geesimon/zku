pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "./tree.circom";

/// @dev calculate secret from two input parameters
//  secret = hash(identityNullifier, identityNullifier)
/// @param (public input signal) identityNullifier: identity nullifier 
/// @param (public input signal) identityTrapdoor: identity trapdoor
/// @output (public output signal) out: secret
template CalculateSecret() {
    signal input identityNullifier;
    signal input identityTrapdoor;

    signal output out;

    component poseidon = Poseidon(2);

    poseidon.inputs[0] <== identityNullifier;
    poseidon.inputs[1] <== identityTrapdoor;

    out <== poseidon.out;
}

/// @dev calcuate identity commitment from Screct
/// identity_commitment = hash(secret)
/// @param (privat input signal) secret: calculated by CalculateSecret()
/// @output (public output signal) out: identity commitment
template CalculateIdentityCommitment() {
    signal input secret;

    signal output out;

    component poseidon = Poseidon(1);

    poseidon.inputs[0] <== secret;

    out <== poseidon.out;
}

/// @dev calcuate nullifier hash
/// nullifier_hash = hash(externalNullifier, identityNullifier)
/// @param (public input signal) externalNullifier: external nullifier
/// @param (private input signal) identityNullifier: identity nullifier
/// @output (public output signal) out: nullifier hash
template CalculateNullifierHash() {
    signal input externalNullifier;
    signal input identityNullifier;

    signal output out;

    component poseidon = Poseidon(2);

    poseidon.inputs[0] <== externalNullifier;
    poseidon.inputs[1] <== identityNullifier;

    out <== poseidon.out;
}

/// @dev build verifier, to verify
/// 1. merkle_root == calculate_merkle_root(identity_commitment, treePathIndices, treeSiblings)
/// 2. nullifierHash == CalculateNullifierHash(externalNullifier, identityNullifier)

/// @param (public input signal) externalNullifier: external nullifier
/// @param (private input signal) identityNullifier: identity nullifier
/// @param (private input signal) treePathIndices: tree path indecies from the leaf to root
/// @param (private input signal) treeSiblings: hash values of the above indecies
/// @param (public input signal) signalHash: hash of signal (string)
/// @param (public input signal) externalNullifier: 
/// @output (public output signal) root: recalculated merkle root from identity_commitment
/// @output (public output signal) nullifierHash: calculated by CalculateNullifierHash()

// nLevels must be < 32.
template Semaphore(nLevels) {
    signal input identityNullifier;
    signal input identityTrapdoor;
    signal input treePathIndices[nLevels];
    signal input treeSiblings[nLevels];

    signal input signalHash;
    signal input externalNullifier;

    signal output root;
    signal output nullifierHash;

    // calcualte secret
    component calculateSecret = CalculateSecret();
    calculateSecret.identityNullifier <== identityNullifier;
    calculateSecret.identityTrapdoor <== identityTrapdoor;

    signal secret;
    secret <== calculateSecret.out;

    // calculate identity commitment, identity commitment is saved in merkle tree
    component calculateIdentityCommitment = CalculateIdentityCommitment();
    calculateIdentityCommitment.secret <== secret;

    // calcualte nullifier hash
    component calculateNullifierHash = CalculateNullifierHash();
    calculateNullifierHash.externalNullifier <== externalNullifier;
    calculateNullifierHash.identityNullifier <== identityNullifier;

    // verify given identity commitment and tree paths info, the calculated merkle root 
    // equals to the saved one
    component inclusionProof = MerkleTreeInclusionProof(nLevels);
    inclusionProof.leaf <== calculateIdentityCommitment.out;

    for (var i = 0; i < nLevels; i++) {
        inclusionProof.siblings[i] <== treeSiblings[i];
        inclusionProof.pathIndices[i] <== treePathIndices[i];
    }

    root <== inclusionProof.root;

    // Dummy square to prevent tampering signalHash.
    signal signalHashSquared;
    signalHashSquared <== signalHash * signalHash;

    // To be used to verfiy signal is only endorsed once 
    nullifierHash <== calculateNullifierHash.out;
}

component main {public [signalHash, externalNullifier]} = Semaphore(20);
