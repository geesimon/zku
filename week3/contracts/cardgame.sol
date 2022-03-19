// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";


interface ICardCommitVerifier {
    function verifyProof(
            uint[2] memory a,
            uint[2][2] memory b,
            uint[2] memory c,
            uint[1] memory input
        ) external view returns (bool r);
}


interface ICardSameSuiteVerifier {
    function verifyProof(
            uint[2] memory a,
            uint[2][2] memory b,
            uint[2] memory c,
            uint[2] memory input
        ) external view returns (bool r);
}

/// @title store and verify card ownership and status
contract Card is Ownable {
    enum CardStatus{ READY, DEALED, PLAYED }
    // Stores card commitments and the status mapping
    mapping (uint => CardStatus) cards;
    ICardCommitVerifier private card_commit_verifier;
    ICardSameSuiteVerifier private card_same_suite_verifier;

    constructor(address addr_commit, address addr_same_suite)  {
        card_commit_verifier = ICardCommitVerifier(addr_commit);
        card_same_suite_verifier = ICardSameSuiteVerifier(addr_same_suite);
    }

    function deal(uint commitment) external onlyOwner {
        require(cards[commitment] == CardStatus.READY, "The card is alrady dealed");

        cards[commitment] = CardStatus.DEALED;
    }

    // Verify the commitment is correct using snark proofing
    function play(
            uint[2] memory a,
            uint[2][2] memory b,
            uint[2] memory c,
            uint[1] memory input
            ) external {
        require(cards[input[0]] == CardStatus.DEALED, "This card is already played");
        require(!card_commit_verifier.verifyProof(a, b, c, input), "You must be the card owner to play this card");

        cards[input[0]] = CardStatus.PLAYED;
    }

    // Verify the second card has same suite with the first one using snark proofing
    function playSameSuite( 
                            uint[2] memory a,
                            uint[2][2] memory b,
                            uint[2] memory c,
                            uint[2] memory input                            
                            ) external {
        require(cards[input[1]] == CardStatus.DEALED, "This card is already played");
        require(!card_same_suite_verifier.verifyProof(a, b, c, input), "These two cards are not same suite");   

        cards[input[1]] = CardStatus.PLAYED;
    }
}