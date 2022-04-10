// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./HarmonyParser.sol";
import "./lib/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
// import "openzeppelin-solidity/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
// import "openzeppelin-solidity/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

/// @title Harmony Light Client deployed on Ethereum.
///        The contract takes Harmony status (as checkpoint block) update from
///        registered relayer(s). To save gas, it only requires checkpoint blocks 
///        and use mmr root to verify any number of Harmony transaction proofs.
contract HarmonyLightClient is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeCast for *;
    using SafeMathUpgradeable for uint256;

    /// @dev Harmony check point block
    struct BlockHeader {
        bytes32 parentHash;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        uint256 number;
        uint256 epoch;
        uint256 shard;
        uint256 time;
        bytes32 mmrRoot;
        bytes32 hash;
    }

    event CheckPoint(
        bytes32 stateRoot,
        bytes32 transactionsRoot,
        bytes32 receiptsRoot,
        uint256 number,
        uint256 epoch,
        uint256 shard,
        uint256 time,
        bytes32 mmrRoot,
        bytes32 hash
    );

    BlockHeader firstBlock;
    BlockHeader lastCheckPointBlock;

    // epoch to block numbers, as there could be >=1 mmr entries per epoch
    mapping(uint256 => uint256[]) epochCheckPointBlockNumbers;

    // block number to BlockHeader
    mapping(uint256 => BlockHeader) checkPointBlocks;

    // epoch to mmr roots
    mapping(uint256 => mapping(bytes32 => bool)) epochMmrRoots;

    /// @dev max relayers
    uint8 relayerThreshold;

    event RelayerThresholdChanged(uint256 newThreshold);
    event RelayerAdded(address relayer);
    event RelayerRemoved(address relayer);

    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "sender doesn't have admin role");
        _;
    }

    modifier onlyRelayers() {
        require(hasRole(RELAYER_ROLE, msg.sender), "sender doesn't have relayer role");
        _;
    }

    function adminPauseLightClient() external onlyAdmin {
        _pause();
    }

    function adminUnpauseLightClient() external onlyAdmin {
        _unpause();
    }

    function renounceAdmin(address newAdmin) external onlyAdmin {
        require(msg.sender != newAdmin, 'cannot renounce self');
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Update max amount of relayers
    function adminChangeRelayerThreshold(uint256 newThreshold) external onlyAdmin {
        relayerThreshold = newThreshold.toUint8();
        emit RelayerThresholdChanged(newThreshold);
    }

    /// @dev Add relayer who can call submitCheckpoint() to update status
    function adminAddRelayer(address relayerAddress) external onlyAdmin {
        require(!hasRole(RELAYER_ROLE, relayerAddress), "addr already has relayer role!");
        grantRole(RELAYER_ROLE, relayerAddress);
        emit RelayerAdded(relayerAddress);
    }

    /// @dev Remove relayer
    function adminRemoveRelayer(address relayerAddress) external onlyAdmin {
        require(hasRole(RELAYER_ROLE, relayerAddress), "addr doesn't have relayer role!");
        revokeRole(RELAYER_ROLE, relayerAddress);
        emit RelayerRemoved(relayerAddress);
    }


    function initialize(
        bytes32 memory firstMMRRoot,
        Proof memory zkrProof,
    ) external initializer {
        MMRRoot = firstMMRRoot;

        require(verify(zkrProof, firstMMRRoot), "invalid recursive proof");

        MMRRoot = zkrProof.output["mmrRoot"];
    }

    function submitCheckpoint(Proof memory zkCheckPointProof) external onlyRelayers whenNotPaused {
        require(verify(zkCheckPointProof, MMRRoot), "invalid recursive proof");

        MMRRoot = zkCheckPointProof.output["mmrRoot"];
    }

    /// @dev retreive the nearest check point block for a given block number
    function getLatestCheckPoint(uint256 blockNumber, uint256 epoch)
        public
        view
        returns (BlockHeader memory checkPointBlock)
    {
        require(
            epochCheckPointBlockNumbers[epoch].length > 0,
            "no checkpoints for epoch"
        );
        uint256[] memory checkPointBlockNumbers = epochCheckPointBlockNumbers[epoch];
        uint256 nearest = 0;
        for (uint256 i = 0; i < checkPointBlockNumbers.length; i++) {
            uint256 checkPointBlockNumber = checkPointBlockNumbers[i];
            if (
                checkPointBlockNumber > blockNumber &&
                checkPointBlockNumber < nearest
            ) {
                nearest = checkPointBlockNumber;
            }
        }
        checkPointBlock = checkPointBlocks[nearest];
    }

    function isValidCheckPoint(uint256 epoch, bytes32 mmrRoot) public view returns (bool status) {
        return epochMmrRoots[epoch][mmrRoot];
    }
}
