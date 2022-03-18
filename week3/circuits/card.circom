pragma circom 2.0.0;

include "../circomlib/circuits/mimcsponge.circom";

/// @title Verify card is commited correctly
/// Need to verfiy:
///       commitment is generated from nullifier, suite and number
/// @input nullifier: a random number
/// @input suite: suite of the card
/// @input number: number of the card
/// @output commitment: hash(nullifier, suite, number)
template CardCommitment() {
    signal input nullifier;
    signal input suite;
    signal input number;
    signal output commitment;

    component mimc = MiMCSponge(3, 220, 1);
    mimc.ins[0] <-- nullifier;
    mimc.ins[1] <-- suite;    
    mimc.ins[2] <-- number;
    mimc.k <-- 0;
    commitment <== mimc.outs[0];
}

/// @title Check 2 cards have same suite
/// Need to verify:
///             1. Both cards are commited correctly
///             2. Two cards have same suite
template CheckSuite() {
    signal input first_nullifier;
    signal input first_suite;
    signal input first_number;
    signal input second_nullifier;
    signal input second_suite;
    signal input second_number;
    signal output first_commitment;
    signal output second_commitment;

    // Calculate and verify the commitment of first card
    component first_card = CardCommitment();
    first_card.nullifier <== first_nullifier;
    first_card.suite <== first_suite;
    first_card.number <== first_number;
    first_card.commitment ==> first_commitment;

    // Calculate and verify the commitment of second card
    component second_card = CardCommitment();
    second_card.nullifier <== second_nullifier;
    second_card.suite <== second_suite;
    second_card.number <== second_number;
    second_card.commitment ==> second_commitment;

    // Check two cards have same suite
    first_suite === second_suite;
}

/// @title Check a card is specific number without
/// @input number_to_reveal: the number need to verify
template RevealNumber() {
    signal input nullifier;
    signal input suite;
    signal input number;
    signal input number_to_reveal;
    signal output commitment;

    // Calculate and verify the commitment of the card
    component card = CardCommitment();
    card.nullifier <== nullifier;
    card.suite <== suite;
    card.number <== number;
    card.commitment ==> commitment;

    // Check the card number is a equal to a specific number
    number === number_to_reveal;
}

component main = CheckSuite();