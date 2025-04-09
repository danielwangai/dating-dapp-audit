// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/MultiSig.sol";  // Assuming MultiSigWallet is in the same directory
import "./ReentrancyAttacks.sol";  // Assuming the attacker contract is in the same directory

contract MultiSigWalletTest is Test {
    MultiSigWallet wallet;
    MultiSigAttack attacker;
    address attackAddress = address(1);
    address owner2 = address(2); // owner 2 is attacker
    // address attackAddress = address(3);

    uint256 initialBalance = 10 ether;

    // Event definitions to capture events
    event TransactionExecuted(uint256 indexed txId, address indexed to, uint256 value);

    function setUp() public {
        // Deploy the MultiSig wallet and the attacker contract
        wallet = new MultiSigWallet(attackAddress, owner2);
        attacker = new MultiSigAttack(address(wallet));

        // Fund the wallet
        vm.deal(address(wallet), initialBalance);

        // Make sure the wallet is set up correctly
        assertEq(wallet.attackAddress(), attackAddress);
        assertEq(wallet.owner2(), attackAddress);
    }

    function testAttackViaReentrancy() public {
        // Setup the transaction by one of the owners
        vm.prank(attackAddress);  // Simulate that owner1 is submitting the transaction
        wallet.submitTransaction(owner2, initialBalance);  // Attack address will receive 1 ether

        // The transaction is now created, and we proceed to approve it

        // Approve the transaction by both owners
        vm.prank(attackAddress);
        wallet.approveTransaction(0);  // Owner1 approves
        vm.prank(owner2);
        wallet.approveTransaction(0);  // Owner2 approves

        // Now, we trigger the attack by calling the attacker's attack function
        vm.prank(attackAddress);  // One of the owners executes the transaction
        wallet.executeTransaction(0);  // Execute the transaction

        // The attack contract will now exploit the vulnerability and attempt to drain funds during the call

        // Assert that the attack contract has successfully drained the wallet
        uint256 finalBalance = address(wallet).balance;
        assertEq(finalBalance, 0, "Wallet balance should be drained by the attacker");

        // Optionally, check that the attacker successfully stole the funds
        uint256 attackerBalance = address(attacker).balance;
        assertEq(attackerBalance, 10 ether, "Attacker should have stolen 1 ether");
    }
}
