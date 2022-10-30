// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./IUniswapV2Router02.sol";
import "./Rewards.sol";
import "./RewardsWithDividend.sol";
import "./RewardsWithDividendWithBurnLP.sol";

contract OG is ERC20, ERC20Burnable, Pausable, Ownable {
  using SafeERC20 for IERC20;

  mapping(address => bool) private liquidityPool;
  mapping(address => bool) private whitelistTax;
  mapping(address => uint256) private lastTrade;

  mapping(address => address) public inviters;

  uint8 private nftTax;
  uint8 private foundationTax;
  uint8 private burnTax;
  uint8 private tradeCooldown;
  uint256 private airdropThreshold;
  address private foundation;
  address public uniswapRouter;
  address public uniswapPair;         //need set after deploy!!
  address public weth;
  address public usdt;

  SignatureRewards public nftRewardsPool;
  SignatureRewardsWithDividendWithBurnLP public lpRewardPool;
  SignatureRewardsWithDividend public txRewardPool;

  event changeTax(uint8 _nftTax, uint8 _foundationTax, uint8 _burnTax);
  event changeAirdropThreshold(uint256 _t);
  event changeCooldown(uint8 tradeCooldown);
  event changeLiquidityPoolStatus(address lpAddress, bool status);
  event changeWhitelistTax(address _address, bool status);
  event changeNftRewardsPool(address nftRewardsPool);
  event changeFoundation(address nftRewardsPool);
  event changeUniswapRouter(address uniswapRouter);
  event changeUniswapPair(address uniswapPair);


  constructor() ERC20("OG", "OG") {
    
    nftTax = 1;
    foundationTax = 2;
    burnTax = 0;
    tradeCooldown = 0;
    airdropThreshold = 2 * 10 ** 17;    //5u

    foundation = 0x9B374AC6E4B7B4A1D4312fe92B472025E1743874;
    uniswapRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    weth = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    usdt = 0x55d398326f99059fF775485246999027B3197955;
    
    _approve(address(this), uniswapRouter, type(uint256).max);
    whitelistTax[address(0)] = true;
    whitelistTax[address(this)] = true;
    whitelistTax[msg.sender] = true;
    whitelistTax[foundation] = true;
    liquidityPool[uniswapRouter] = true;

    nftRewardsPool= new SignatureRewards(address(0x1fb9Ab830bDc0391B1b2f8903d0aF08759003323), address(this));
    lpRewardPool = new SignatureRewardsWithDividendWithBurnLP(address(0x1fb9Ab830bDc0391B1b2f8903d0aF08759003323), address(this));
    txRewardPool = new SignatureRewardsWithDividend(address(0x1fb9Ab830bDc0391B1b2f8903d0aF08759003323), address(this));
    nftRewardsPool.transferOwnership(msg.sender);
    lpRewardPool.transferOwnership(msg.sender);
    txRewardPool.transferOwnership(msg.sender);
    whitelistTax[address(nftRewardsPool)] = true;
    whitelistTax[address(lpRewardPool)] = true;
    whitelistTax[address(txRewardPool)] = true;

    _mint(msg.sender, 40_000_000_000 * 1000000);
    _mint(address(lpRewardPool), 30_000_000_000 * 1000000);
    _mint(address(txRewardPool), 30_000_000_000 * 1000000);

  }
  
  function decimals() public view virtual override returns (uint8) {
        return 6;
  }

  function pause() public onlyOwner {
      _pause();
  }

  function unpause() public onlyOwner {
      _unpause();
  }

  function setTaxes(uint8 _nftTax, uint8 _foundationTax, uint8 _burnTax) external onlyOwner {
    nftTax = _nftTax;
    foundationTax = _foundationTax;
    burnTax = _burnTax;
    emit changeTax(_nftTax,_foundationTax,_burnTax);
  }

  function setAirdropThreshold(uint256 _t) external onlyOwner {
    airdropThreshold = _t;
    emit changeAirdropThreshold(_t);
  }

  function getTaxes() external pure returns (uint8 _nftTax, uint8 _foundationTax, uint8 _burnTax) {
    return (_nftTax, _foundationTax, _burnTax);
  }

  function setCooldownForTrades(uint8 _tradeCooldown) external onlyOwner {
    tradeCooldown = _tradeCooldown;
    emit changeCooldown(_tradeCooldown);
  }

  function setLiquidityPoolStatus(address _lpAddress, bool _status) external onlyOwner {
    liquidityPool[_lpAddress] = _status;
    emit changeLiquidityPoolStatus(_lpAddress, _status);
  }

  function setWhitelist(address _address, bool _status) external onlyOwner {
    whitelistTax[_address] = _status;
    emit changeWhitelistTax(_address, _status);
  }

  function setRewardsPool(address _nftRewardsPool) external onlyOwner {
    nftRewardsPool = SignatureRewards(_nftRewardsPool);
    emit changeNftRewardsPool(_nftRewardsPool);
  }

  function setFoundation(address _foundation) external onlyOwner {
    foundation = _foundation;
    emit changeFoundation(_foundation);
  }

  function setUniswapRouter(address _uniswapRouter) external onlyOwner {
    uniswapRouter = _uniswapRouter;
    IERC20(address(this)).approve(_uniswapRouter, type(uint256).max);
    liquidityPool[_uniswapRouter] = true;
    emit changeUniswapRouter(_uniswapRouter);
  }

  function setUniswapPair(address _uniswapPair) external onlyOwner {
    uniswapPair = _uniswapPair;
    liquidityPool[_uniswapPair] = true;
    emit changeUniswapPair(_uniswapPair);
  }

  function getMinimumAirdropAmount() private view returns (uint256) {
    uint256[] memory amounts = IUniswapV2Router02(uniswapRouter).getAmountsIn(airdropThreshold, getPathForTokenToToken(address(this), usdt));
    return amounts[0];
  }

  // function getExactUSDTokenAmount(uint256 value) public view returns (uint256) {
  //   uint256[] memory amounts = IUniswapV2Router02(uniswapRouter).getAmountsIn(value, getPathForTokenToToken(address(this), usdt));
  //   return amounts[0];
  // }

  function getInviter(address who, uint256 n) public view returns (address[] memory) {
    address[] memory inviters_ = new address[](n);
    address temp = who;

    for (uint256 index = 0; index < n; index++) {
      temp = inviters[temp];
      inviters_[index] = temp == who ? address(0) : temp;

    }

    return inviters_;
  }






  function _transfer(address sender, address receiver, uint256 amount) internal virtual override {
    uint256 taxAmount0 = ( amount * nftTax ) / 100;
    uint256 taxAmount1 = ( amount * foundationTax ) / 100;
    uint256 taxAmount2 = ( amount * burnTax ) / 100;

    if(liquidityPool[receiver] == true) {      
      //It's an LP Pair and it's a sell
      require(lastTrade[sender] < (block.timestamp - tradeCooldown), string("No consecutive sells allowed. Please wait."));
      lastTrade[sender] = block.timestamp;
    } 

    if(whitelistTax[sender] || whitelistTax[receiver]) {
      taxAmount0 = 0;
      taxAmount1 = 0;
      taxAmount2 = 0;
    }

    if( liquidityPool[sender] == true && liquidityPool[receiver] == true ) {
      taxAmount0 = 0;
      taxAmount1 = 0;
      taxAmount2 = 0;
    }

    
    if(taxAmount0 > 0) {
      super._transfer(sender, address(nftRewardsPool), taxAmount0);
    }  
    if(taxAmount1 > 0) {

      if(liquidityPool[sender] == true){
        //buy
        super._transfer(sender, foundation, taxAmount1);
      }
      else{
        //transfer or sell
        super._transfer(sender, address(this), taxAmount1);
        IUniswapV2Router02(uniswapRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(taxAmount1, 0, getPathForTokenToToken(address(this), usdt), foundation, block.timestamp + 1 days); //swapExactTokensForTokens
      }
    } 

    if(taxAmount2 > 0) {
      _burn(sender, taxAmount2);
    }   

    super._transfer(sender, receiver, amount - taxAmount0 - taxAmount1 - taxAmount2);
  }

  function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal whenNotPaused override {
    //require(_to != address(this), string("No transfers to contract allowed."));    
    if(inviters[_to] == address(0) && !liquidityPool[_from] && !liquidityPool[_to] && !whitelistTax[_from] && !whitelistTax[_to] && _amount >= getMinimumAirdropAmount()) inviters[_to] = _from;
    super._beforeTokenTransfer(_from, _to, _amount);
  }

  function getPathForTokenToToken(address _tokenIn, address _tokenOut) private pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;
        
        return path;
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