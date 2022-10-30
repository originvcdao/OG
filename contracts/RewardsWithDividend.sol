//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./OG.sol";

contract SignatureRewardsWithDividend is Ownable {
  using ECDSA for bytes32;
  using SafeERC20 for IERC20;

  address private _systemAddress;
  address public reward;
  uint8[] public dividendRate = [70,15,3,3,3,3,3];
  mapping(string => bool) public usedNonces;
  mapping(address => uint256) public claimed;

  constructor(address signedAddress, address rewardAddress) {
    _systemAddress = signedAddress;
    reward = rewardAddress;
  }

  function setDividendRate(uint8[] memory _dividendRate) external onlyOwner {
    dividendRate = _dividendRate;
  }

  function claim(
      uint256 amount,
      string memory nonce,
      bytes32 hash,
      bytes memory signature
    ) external payable {
  
      // signature realted
      require(matchSigner(hash, signature), "Plz mint through website");
      require(!usedNonces[nonce], "Hash reused");
      require(
        hashTransaction(msg.sender, amount, nonce) == hash,
        "Hash failed"
      );


      IERC20(reward).safeTransfer(msg.sender, (amount - claimed[msg.sender]) * dividendRate[0] / 100);   
      distributeDividend(msg.sender, amount - claimed[msg.sender]);

      usedNonces[nonce] = true;
      claimed[msg.sender] = amount;     //amount never decrease
  }

  function distributeDividend(address from, uint256 amount) internal {
    address[] memory inviters = OG(reward).getInviter(from, 6);

    for (uint256 index = 0; index < inviters.length; index++) {
      if( inviters[index] != address(0) ) { 
        IERC20(reward).safeTransfer(inviters[index], amount * dividendRate[index + 1] / 100 );
      }
      else{
        ERC20Burnable(reward).burn(amount * dividendRate[index + 1] / 100);
      }
    }
  }

  
  
  function matchSigner(bytes32 hash, bytes memory signature) public view returns (bool) {
    return _systemAddress == hash.toEthSignedMessageHash().recover(signature);
  }

  function hashTransaction(
      address sender,
      uint256 amount,
      string memory nonce
    ) public view returns (bytes32) {
    
      bytes32 hash = keccak256(
        abi.encodePacked(sender, amount, nonce, address(this))
      );

      return hash;
  }

  function rescure() public payable onlyOwner {
    uint balance = address(this).balance;
    require(balance > 0, "No ether left to withdraw");

    (bool success, ) = (msg.sender).call{value: balance}("");
    require(success, "Transfer failed.");
  }

  function rescure(address token) public onlyOwner {
    IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
  }


}