pragma circom 2.0.0;

include "../circomlib/circuits/comparators.circom";

/// @title Verify an absolute vaule is less or equal than another uint value
/// @param bits:　number of bits the input have
/// @input in: the value need to compare
/// @input max_abs_value: the unit value abs(in) need less than or equal
/// @output: none
/// Need to verify: abs(in) <= max_abs_value
template RangeProof(bits) {
    signal input in;
    signal input max_abs_value;

    component lowerBound = LessEqThan(bits);
    component upperBound = LessEqThan(bits);

    lowerBound.in[0] <== max_abs_value + in;
    lowerBound.in[1] <== 0;
    lowerBound.out === 0;

    upperBound.in[0] <== 2 * max_abs_value;
    upperBound.in[1] <== max_abs_value + in;
    upperBound.out === 0;
}

/// @param n: n field elements, whose abs are claimed to be less than max_abs_value
/// @param bits: number of bits the input have
/// @input in[n]: the values need to compare
/// @input max_abs_value: the unit value abs(in) need less than or equal
/// @output: none
template MultiRangeProof(n, bits) {
    signal input in[n];
    signal input max_abs_value;
    component rangeProofs[n];

    for (var i = 0; i < n; i++) {
        rangeProofs[i] = RangeProof(bits);
        rangeProofs[i].max_abs_value <== max_abs_value;
        rangeProofs[i].in <== in[i];
    }
}