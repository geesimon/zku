// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Base64.sol";

/// @title Solidity implementation of Merkle Tree
contract MerkleTree {
    // Store hashes in a 2-dimension array. 
    // First dimension for tree layers and second store siblings of same layer.
    // Compared with other complex data structure (i.e., mapping, structure),
    // use this simple data structure can reduce storage usage, computation complexity 
    // and gas consumption

    uint256[][] internal _HashTree;
 
    // Value of leaves. 
    // Note: this variable should be internal use only,
    // we make it public for debugging purpose.
    string [] public leaves;

    function addLeaf (string memory value) public returns (uint256){
        leaves.push(value);     // Store new data

        // Make the leaf layer if not exists
        if (_HashTree.length == 0){
            _addNewLayer();
        }
        // Calculate and store hash for this now leaf
        uint256 _hash;
        
        _hash = uint256(keccak256(bytes(value)));
        _HashTree[0].push(_hash);

        // Instead of rebuilding the entire tree, we only 
        // update/add the impacted tree node, which is the last
        // node of each layer. This can reduce gas consumption.
        uint _layer = 0;
        uint256 _leftValue;
        uint256 _rightValue;

        // Loop through all layers
        while (_HashTree[_layer].length > 1){
            if (_HashTree[_layer].length % 2 == 1) {
                // Odd node, need to add new parent
                // This is the left node, we will use same value 
                // to build parent hash.
                _leftValue = _HashTree[_layer][_HashTree[_layer].length - 1];
                _rightValue = _leftValue;
                // Create new layer if it does not exist
                if (_layer == _HashTree.length - 1) {
                    _addNewLayer();
                }
                _hash = uint256(keccak256(abi.encodePacked(_leftValue, _rightValue)));     
                _HashTree[_layer + 1].push(_hash);
            } else {
                // Even node
                // This is the right node, we will need to use left node 
                // to build parent hash.
                _leftValue = _HashTree[_layer][_HashTree[_layer].length - 2];
                _rightValue = _HashTree[_layer][_HashTree[_layer].length - 1];
                _hash = uint256(keccak256(abi.encodePacked(_leftValue, _rightValue)));
                // Create new layer if it does not exist
                if (_layer == _HashTree.length - 1) {
                    _addNewLayer();
                    // Add parent to the new layer
                    _HashTree[_layer + 1].push(_hash);
                } else {
                    // Update exisitng parent
                    _HashTree[_layer + 1][_HashTree[_layer + 1].length - 1] = _hash;
                }
            }
            _layer++;
        }

        return _hash;
    }

    function _addNewLayer() private {
        uint256[] memory newLayer;
        _HashTree.push(newLayer);
    }

    function getLeafCount() public view returns (uint256){
        return _HashTree[0].length;
    }

    function getRootHash() 
        public view returns (uint256) {
        return _HashTree[_HashTree.length - 1][0];
    }
}

/// @title Use Merkle Tree to store NFT transaction records
contract MerkleTreeNFT is MerkleTree {
    /// @dev Call this function to record NFT transactions in this MerkleTree contract
    /// @param sender: sender of the NFT token
    /// @param receiver: receiver of the NFT token
    /// @param tokenId: token ID
    /// @param tokenURI: meta data for this NFT token
    function commitNFTTransactions(address sender, address receiver, 
                                    uint256 tokenId, string memory tokenURI)
        public returns (uint256) {
        // Encode these info and convert to base64 string
        return addLeaf(Base64.encode(abi.encodePacked(sender, 
                                                        receiver, 
                                                        tokenId, 
                                                        tokenURI)));
    }
}