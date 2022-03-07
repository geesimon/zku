// contracts/GameItem.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/// @title interface to access MerkleTreeNFT contract
interface IMerkleTreeNFT {
    function commitNFTTransactions(address sender, address receiver, 
                                    uint256 tokenId, string memory tokenURI)
        external returns (uint256);
}

/// @title a toy NFT contract that implement ERC721 and ERC721URIStorage
/// It includes the metadata standard extensions (name, description),
/// and stores transaction record onchina in Merkle Tree
contract ToyNFT is ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    IMerkleTreeNFT private merkle_tree;

    constructor(address addr) ERC721("ToyNFT", "ITM") {
        merkle_tree = IMerkleTreeNFT(addr);
    }

    /// @dev transfer NFT token with metadata and record transaction 
    /// in a merkle tree.
    /// @param player: NFT token receiver
    /// @param name: NFT token name
    /// @param description: NFT token description
    function awardItem(address player, 
        string memory name, string memory description)
        public
        returns (uint256)
    {
        _tokenIds.increment();

        uint256 newItemId = _tokenIds.current();
        _mint(player, newItemId);

        string memory uri = tokenURI(name, description);
        _setTokenURI(newItemId, uri);
        
        // Record transaction in merkle tree
        merkle_tree.commitNFTTransactions(msg.sender, player, newItemId, uri);

        return newItemId;
    }

    /// @dev encode metadata enfo using base64
    /// @param name: NFT token name
    /// @param description: NFT token description
    function tokenURI(string memory name, string memory description)
        public
        pure
        returns (string memory)
    {
        bytes memory dataURI = abi.encodePacked(
            '{',
                '"name": ', name, '"',
                '"description": ', description, '"',
            '}'
        );

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(dataURI)
            )
        );
    }
}