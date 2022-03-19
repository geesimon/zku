// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface ITriangleJumpVerifier {
    function verifyProof(
            uint[2] memory a,
            uint[2][2] memory b,
            uint[2] memory c,
            uint[5] memory input
        ) external view returns (bool r);
}

/// @title Record moves by game players
/// only implemented triangle jump move for simplicity
contract DarkForestMove {
    ITriangleJumpVerifier private jump_verifier;

    // Stores player -> locations map
    mapping(address => mapping(uint => bool)) public player_locations;

    constructor(address addr)  {
        jump_verifier = ITriangleJumpVerifier(addr);
    }

/// @dev Verify the snark proof (defined in triangeljump.circom),
///      and stores B, C locations in occupations
    function triangleJump (
            uint[2] memory a,
            uint[2][2] memory b,
            uint[2] memory c,
            uint[5] memory input) external {

        require(jump_verifier.verifyProof(a, b, c, input), 
                    "Need valid triangle jump proof from client");
                
        player_locations[msg.sender][input[1]] = true;
        player_locations[msg.sender][input[2]] = true;
    }
}