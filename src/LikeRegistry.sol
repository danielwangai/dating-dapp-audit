// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./SoulboundProfileNFT.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./MultiSig.sol";

contract LikeRegistry is Ownable {
    struct Like {
        address liker;
        address liked;
        uint256 timestamp;
    }

    SoulboundProfileNFT public profileNFT;

    uint256 immutable FIXEDFEE = 10;
    uint256 totalFees;

    mapping(address => mapping(address => bool)) public likes;
    mapping(address => address[]) public matches;
    // q mapping of user address to sum of all like-charges?
    mapping(address => uint256) public userBalances;

    event Liked(address indexed liker, address indexed liked);
    event Matched(address indexed user1, address indexed user2);

    constructor(address _profileNFT) Ownable(msg.sender) {
        profileNFT = SoulboundProfileNFT(_profileNFT);
    }

    // q where is the natspec?
    // q info likeUser not used
    function likeUser(address liked) external payable {
        // @✅audit gas - create and error for this and use if-revert
        // q documentation says amount per like is 1ETH.
        // does this allow a like tto be potentially > 1ETH?
        // qanswered
        require(msg.value >= 1 ether, "Must send at least 1 ETH");
        // @✅audit gas - create and error for this and use if-revert
        require(!likes[msg.sender][liked], "Already liked");
        // @✅audit gas - create and error for this and use if-revert
        require(msg.sender != liked, "Cannot like yourself");
        // @✅audit gas - create and error for this and use if-revert
        require(profileNFT.profileToToken(msg.sender) != 0, "Must have a profile NFT");
        // @✅audit gas - create and error for this and use if-revert
        require(profileNFT.profileToToken(liked) != 0, "Liked user must have a profile NFT");

        likes[msg.sender][liked] = true;
        emit Liked(msg.sender, liked);

        // Check if mutual like
        if (likes[liked][msg.sender]) {
            matches[msg.sender].push(liked);
            matches[liked].push(msg.sender);
            emit Matched(msg.sender, liked);
            matchRewards(liked, msg.sender);
        }
    }

    // q no natspec here
    // 
    function matchRewards(address from, address to) internal {
        // @audit suggestion - naming could be better e.g. userOneBalance & userTwoBalance
        uint256 matchUserOne = userBalances[from];
        uint256 matchUserTwo = userBalances[to];
        userBalances[from] = 0;
        userBalances[to] = 0;

        uint256 totalRewards = matchUserOne + matchUserTwo;
        uint256 matchingFees = (totalRewards * FIXEDFEE) / 100;
        uint256 rewards = totalRewards - matchingFees;
        totalFees += matchingFees;

        // Deploy a MultiSig contract for the matched users
        MultiSigWallet multiSigWallet = new MultiSigWallet(from, to);

        // Send ETH to the deployed multisig wallet
        // slither-disable-next-line low-level-calls
        (bool success,) = payable(address(multiSigWallet)).call{value: rewards}("");
        // @✅audit gas - create and error for this and use if-revert
        require(success, "Transfer failed");
    }

    function getMatches() external view returns (address[] memory) {
        return matches[msg.sender];
    }

    function withdrawFees() external onlyOwner {
        // @✅audit gas - create and error for this and use if-revert
        require(totalFees > 0, "No fees to withdraw");
        uint256 totalFeesToWithdraw = totalFees;

        totalFees = 0;
        // slither-disable-next-line low-level-calls
        (bool success,) = payable(owner()).call{value: totalFeesToWithdraw}("");
        // @✅audit gas - create and error for this and use if-revert
        require(success, "Transfer failed");
    }

    /// @notice Allows the contract to receive ETH
    receive() external payable {}
}
