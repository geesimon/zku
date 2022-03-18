#!/bin/sh

#######################
# Color Code
#######################
Green_font_prefix="\033[32m" 
Red_font_prefix="\033[31m"
Green_background_prefix="\033[42;37m"
Red_background_prefix="\033[41;37m" 
Font_color_suffix="\033[0m"

#######################
# Utility functions
#######################

# Show Help Info
show_help() {
    echo
    echo "Compile, generate witness and prove files for a circom circuits file using Groth16 zk-SNARK protocol"
    echo
    echo "USAGE:"
    echo "      $0 <circom file> <input file>"
    echo
    echo "OUTPUT:"
    echo "       [Compiled circuits file: <circom>.r1cs]"
    echo "       [<circom>_js folder: Wasm code to genereate witness]"
    echo "       [<proof> folder: circuit trusted setup files, verification files]"
    echo
}

# Check the existence of file and exit if not
check_file() {
    if ! [ -f $1 ]; then
        echo
        echo "${Red_font_prefix}File <$1> does not exists!"${Font_color_suffix}
        echo
        exit
    fi
}

# Main Logic Start Here

# Show help info if parameter is not given correctly
if [ "$#" -ne 2 ] || [ "$1" = "--help" ]; then
    show_help
    exit
fi
check_file $1
check_file $2

circom_file=$1
input_file=$2
base_name=${circom_file%.*}

# Exit the shell on error and show command
set -e
set -x
#######################
# Compiling our circuit
#######################
wasm_folder=${base_name}_js
proof_folder="${base_name}_proof"

# Clean old files
if [ -d $wasm_folder ]; then
    rm $wasm_folder/*
    rmdir $wasm_folder
fi
if [ -f {base_name}.r1cs ]; then
    rm {base_name}.r1cs
fi
if [ -d $proof_folder ]; then
    rm $proof_folder/*
    rmdir $proof_folder
fi

# Compile the circuit to get a system of arithmetic equations representing it
circom $circom_file --r1cs --wasm

#######################
# Computing our witness
#######################

cd $wasm_folder

# Computing the witness with WebAssembly
node generate_witness.js ${base_name}.wasm ../${input_file} witness.wtns
cd ..

#######################
# Proving circuits
#######################
mkdir $proof_folder
cd $proof_folder

public_file=${base_name}_public.json
proof_file=${base_name}_proof.json
verification_file=${base_name}_verification_key.json

# Start a new "powers of tau" ceremony
snarkjs powersoftau new bn128 16 pot16_0000.ptau -v
# Contribute to the ceremony, use timestamp as the random text
printf "$(date +%s)\n" | snarkjs powersoftau contribute pot16_0000.ptau pot16_0001.ptau --name="First contribution" -v

# Start the generation of phase 2
snarkjs powersoftau prepare phase2 pot16_0001.ptau pot16_final.ptau -v
# Generate a .zkey file that will contain the proving and verification keys together 
# with all phase 2 contributions
snarkjs groth16 setup ../${base_name}.r1cs pot16_final.ptau ${base_name}_0000.zkey
# Contribute to the phase 2 of the ceremony, use timestamp as the random text
printf "$(date +%s)\n" | snarkjs zkey contribute ${base_name}_0000.zkey ${base_name}_0001.zkey --name="First Contributor" -v
# Export the verification key
snarkjs zkey export verificationkey ${base_name}_0001.zkey $verification_file

# Generate a Proof
snarkjs groth16 prove ${base_name}_0001.zkey ../${wasm_folder}/witness.wtns $proof_file $public_file

# Verify a Proof
snarkjs groth16 verify $verification_file $public_file $proof_file

# Generate a Solidity verifier that allows verifying proofs on Ethereum blockchain
snarkjs zkey export solidityverifier ${base_name}_0001.zkey ${base_name}_verifier.sol

snarkjs zkey export soliditycalldata ${base_name}_public.json ${base_name}_proof.json > ${base_name}_verifier.call.txt