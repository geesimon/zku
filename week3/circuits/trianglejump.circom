pragma circom 2.0.0;

include "../circomlib/circuits/mimcsponge.circom";
include "rangecheck.circom";

/// @title implements a triangle jump.
/// A player hops from planet A to B then to C and returns to A
/// all in one move, such that A, B, and C lie on a triangle.
/// Need to verify:
///     1. A, B, C within the space range.
///     2. The move lies (A → B → C → A) on a triangle.
///     3. Move distances (A → B and B → C) are within the energy 
///        level.
///     4. A, B, C hashes are computed correctly.
/// @input a_x: x coordinate of planet A
/// @input a_y: y coordinate of planet A
/// @input b_x: x coordinate of planet B
/// @input b_x: y coordinate of planet B
/// @input c_x: x coordinate of planet C
/// @input c_x: y coordinate of planet C
/// @input r: space range
/// @input energy: player's energy level
/// @output A_hash: hash(a_x, a_y)
/// @output B_hash: hash(b_x, b_y)
/// @output C_hash: hash(c_x, c_y)
template TriangleJump() {
    signal input a_x;
    signal input a_y;
    signal input b_x;
    signal input b_y;
    signal input c_x;
    signal input c_y;

    signal input r;
    signal input energy;

    signal output A_hash;
    signal output B_hash;
    signal output C_hash;

    // Check all A, B, C are within the space range (r)
    component points_rp = MultiRangeProof(3, 32);
    points_rp.max_abs_value <== r ** 2;
    points_rp.in[0] <-- a_x ** 2 + a_y ** 2;
    points_rp.in[1] <-- b_x ** 2 + b_y ** 2;
    points_rp.in[2] <-- c_x ** 2 + c_y ** 2;

    // Check A, B, C makes a triangel:
    // a_x * (b_y - c_y) + b_x * (c_y - a_y) + c_x * (a_y - b_y) != 0
    signal area;
    area <-- a_x * (b_y - c_y) + b_x * (c_y - a_y) + c_x * (a_y - b_y);
    component is_zero = IsZero();
    is_zero.in <== area;
    is_zero.out === 0;

    // Check each jump is within energy level.
    // ab^2 <= energy^2, bc^2 <= energy^2, ca^2 <= energy^2
    signal ab_x;
    signal ab_y;
    signal bc_x;
    signal bc_y;
    signal ca_x;
    signal ca_y;
    signal ab_distance_square;
    signal bc_distance_square;
    signal ca_distance_square;
    signal energy_square;

    ab_x <-- a_x - b_x;
    ab_y <-- a_y - b_y;
    ab_distance_square <-- ab_x ** 2 + ab_y ** 2;
    bc_x <-- b_x - c_x;
    bc_y <-- b_y - c_y;
    bc_distance_square <-- bc_x ** 2 + bc_y ** 2;
    ca_x <-- c_x - a_x;
    ca_y <-- c_y - c_y;
    ca_distance_square <-- ca_x ** 2 + ca_y ** 2;
    energy_square <-- energy ** 2;

    component dist_rp = MultiRangeProof(3, 32);
    dist_rp.max_abs_value <== energy ** 2;
    dist_rp.in[0] <-- ab_distance_square;
    dist_rp.in[1] <-- bc_distance_square;
    dist_rp.in[2] <-- ca_distance_square;

    // Verify MiMCSponge(a_x, a_y) == A_hash
    component mimc_a = MiMCSponge(2, 220, 1);
    mimc_a.ins[0] <-- a_x;
    mimc_a.ins[1] <-- a_y;
    mimc_a.k <-- 0;
    A_hash <== mimc_a.outs[0];

    // Verify MiMCSponge(b_x, b_y) == B_hash
    component mimc_b = MiMCSponge(2, 220, 1);
    mimc_b.ins[0] <-- b_x;
    mimc_b.ins[1] <-- b_y;
    mimc_b.k <-- 0;
    B_hash <== mimc_b.outs[0];

    // Verify MiMCSponge(c_x, c_y) == C_hash
    component mimc_c = MiMCSponge(2, 220, 1);
    mimc_c.ins[0] <-- c_x;
    mimc_c.ins[1] <-- c_y;
    mimc_c.k <-- 0;
    C_hash <== mimc_c.outs[0];
}

component main {public [r, energy]} = TriangleJump();
