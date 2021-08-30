//SPDX-License-Identifier:MIT
pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

import "./interfaces/IUniswapV3Factory.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IERC20.sol";
import "./libraries/TickMath.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
/**
 * @title Vault C : The position has rare range.
 * 45% of total reward will assign to the Vault A.
 */

contract PlethoriVaultC {
    struct Deposit {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 blockNumber;
    }

    IUniswapV3Factory public factory;

    INonfungiblePositionManager public nonfungiblePositionManager;

    IERC20 public rewardToken;

    address public feeAddress;
    uint256 public REWARD_INTERVAL = 365 days;
    uint256 public WITHDRAW_FEE = 150;
    address public admin;
    mapping(uint256 => Deposit) public deposits;

     AggregatorV3Interface internal priceFeed;

    modifier onlyAdmin() {
        require(msg.sender == admin, "The caller is not admin.");
        _;
    }

    constructor(
        IUniswapV3Factory _factory,
        INonfungiblePositionManager _nonfungiblePositionManager,
        IERC20 _rewardToken,
        address _feeAddress,
        address _admin
    ) {
        factory = _factory;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        rewardToken = _rewardToken;
        feeAddress = _feeAddress;
        admin = _admin;
          priceFeed = AggregatorV3Interface(
            0x3873965e73d9a21f88e645ce40b7db187fde4931
        );
    }

    function getRewardBalance() internal view returns (uint256) {
        return IERC20(rewardToken).balanceOf(address(this));
    }

    function getCurrentBlockNumber(uint256 tokenId)
        internal
        view
        returns (uint256)
    {
        return block.number - deposits[tokenId].blockNumber;
    }

    /// Reward calculation
    function getPendingReward(uint256 tokenId) internal view returns (uint256) {
        if (deposits[tokenId].liquidity == 0) return 0;
        if (IERC20(rewardToken).balanceOf(address(this)) == 0) return 0;
        uint256 pendingReward = (deposits[tokenId].liquidity *
            getCurrentBlockNumber(tokenId)) /
            (REWARD_INTERVAL * 24 * 60 * 60) /
            12;
        return pendingReward;
    }

    function deposit(uint256 tokenId) external {
        require(tokenId > 0, "NFT tokenId can not be zero.");
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        // get position information
        (tickLower, tickUpper, liquidity) = getPositionInfo(tokenId);
        require(getLatestTicker() > tickUpper,"This NFT position can not deposit here.");
        
        if(!deposits[tokenId].point){
          deposits[tokenId] = Deposit({
            owner: msg.sender,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            blockNumber: block.number
           });
       }
    }

    function getPositionInfo(uint256 tokenId)
        internal
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        (
            ,
            ,
            ,
            ,
            ,
            tickLower,
            tickUpper,
            liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);
    }

    function updateVault(address account, uint256 tokenId) internal {
        uint256 pendingDivs = getPendingReward(tokenId);
        if (pendingDivs > 0) {
            uint256 amountAfterFee = (pendingDivs * WITHDRAW_FEE) / 1e4;
            uint256 rewardAfterFee = pendingDivs - amountAfterFee;
            require(
                IERC20(rewardToken).transfer(account, rewardAfterFee),
                "Can not transfer"
            );
            require(
                IERC20(rewardToken).transfer(feeAddress, amountAfterFee),
                "Can not transfer"
            );
        }

        deposits[tokenId].blockNumber = block.number;
    }

    function withdraw(uint256 tokenId) external {
        require(tokenId > 0, "NFT tokenId can not be zero.");
        Deposit memory depositer = deposits[tokenId];
        require(depositer.owner == msg.sender, "only owner can withdraw token");

        delete deposits[tokenId];
    }

    /** @notice onClaim function.
     */
    function onClaim(address userAddress, uint256 tokenId) public {
        require(deposits[tokenId].owner == userAddress, "The claimer is not.");
        updateVault(userAddress, tokenId);
    }

    function withdrawToAdmin() external onlyAdmin {
        uint256 balance = getRewardBalance();
        if (balance > 0) {
            require(
                IERC20(rewardToken).transfer(admin, balance),
                "Can not transfer"
            );
        }
    }

        /**
     * Returns the latest price
     */
    function getLatestPrice() internal view returns (int256) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return price;
    }

    function getLatestTicker() internal view returns (int24) {
        int24 currentTicker = getTickAtSqrtRatio(
            uint160(int160(getLatestPrice()))
        );
        return currentTicker;
    }
}
