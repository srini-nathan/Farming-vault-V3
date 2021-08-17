//SPDX-License-Identifier:MIT
pragma solidity ^0.8.4;

import "./interfaces/IUniswapV3Vault.sol";
import "./libraries/NFTPositionInfo.sol";
import "./libraries/IncentiveId.sol";
import "./libraries/RewardMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IERC20Minimal.sol";

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/base/Multicall.sol";

///@title plethori vault on uniswapV3
///@notice PLE/ETH V3 NFT asset will be locked in PlethoriVaultV3 smart contract.
contract PlethoriVaultV3 is IUniswapV3Vaulter, Multicall {
    ///@notice Represents the deposit of a liquidity NFT

    struct Deposit {
        address owner;
        uint48 numberOfLockes;
        int24 tickLower;
        int24 tickUpper;
    }

    ///@notice Represents a staked liquidity NFT

    struct Stake {
        uint160 secondPerLiquidityInsideInitialX128;
        uint96 liquidityNoOverflow;
        uint128 liquidityIfOverflow;
    }

    ///@inheritdoc IUniswapV3Vaulter
    IUniswapV3Vaulter public immutable override factory;
    ///@inheritdoc IUniswapV3Vaulter

    INonfungiblePositionManager
        public immutable
        override nonfungiblePositionManager;

    /// @inheritdoc IUniswapV3Staker
    uint256 public immutable override maxIncentiveStartLeadTime;
    /// @inheritdoc IUniswapV3Staker
    uint256 public immutable override maxIncentiveDuration;

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public override deposits;

    ///@dev stakes[tokenId][incentiveHash] => Stake
    mapping(uint256 => mapping(bytes32 => Stake)) private _stakes;

    ///@inheritdoc IUniswapV3Vaulter
    function stakes(uint256 tokenId, bytes32 incentiveId)
        public
        view
        override
        returns (
            uint160 secondsPerLiquidityInsideInititalX128,
            uint128 liqudity
        )
    {
        Stake storage stake = _stakes[tokenId][incentiveId];
        secondsPerLiquidityInsideInititalX128 = stake
            .secondPerLiquidityInsideInitialX128;
        liquidity = stake.liquidityNoOverflow;
        if (liquidity == type(uint96).max) {
            liquidity = stake.liquidityIfOverflow;
        }
    }

    ///@dev rewards[rewardToken][owner] => uint256
    ///@inheritdoc IUniswapV3Vaulter
    mapping(IERC20Minimal => mapping(address => uint256))
        public
        override rewards;

    ///@param _factory the Uniswap V3 factory
    ///@param _nonfungiblePositionManager the NFT position manager contract address
    ///@param _maxIncentiveStartLeadTime the max duration of an incentive in seconds
    ///@param _maxIncentiveDuration the max amount of seconds into the future the incentive startTime can be set

    constructor(
        IUniswapV3Factory _factory,
        INonfungiblePositionManager _nonfungiblePositionManager,
        uint256 _maxIncentiveStartLeadTime,
        uint256 _maxIncentiveDuration
    ) {
        factory = _factory;
        nonfungiblePositionManager = _nonfungiblPositionManager;
        maxIncentiveStartLeadTime = _maxIncentiveStartLeadTime;
        maxIncentiveDuration = _maxIncentiveDuration;
    }

    ///@inheritdoc IUniswapV3Vaulter
    function stakeToken(IncentiveKey memory key, uint256 tokenId)
        external
        override
    {
        require(
            deposits[tokenId].owner == msg.sender,
            "UniswapV3Vaulter::stakeTokn: only owner can stake token"
        );
        _stakeToke(key, tokenId);
    }

    ///@inheritdoc IUniswapV3Vaulter
    function unstakeToken(IncentiveKey memory key, uint256 tokenId)
        external
        override
    {
        Deposit memory deposit = deposits[tokenId];

        // anyone can call unstakeToken if the block time is after the end time of the incentive

        if (block.timestamp < key.endTime) {
            require(
                deposit.owner == msg.sender,
                "only owner can withdraw token before incentive end time"
            );
        }

        bytes32 incentiveId = IncentiveId.compute(key);
        (
            uint160 secondsPerLiquidityInsideInitialX128,
            uint128 liquidity
        ) = stakes(tokenId, incentiveId);

        require(
            liquidity != 0,
            "UniswapV3Staker::unstakeToken: stake does not exist"
        );

        Incentive storage incentive = incentives[incentiveId];

        deposits[tokenId].numberOfStakes--;
        incentive.numberOfStakes--;

        (, uint160 secondsPerLiquidityInsideX128, ) = key
            .pool
            .snapshotCumulativesInside(deposit.tickLower, deposit.tickUpper);

        (uint256 reward, uint160 secondsInsideX128) = RewardMath
            .computeRewardAmount(
                incentive.totalRewardUnclaimed,
                incentive.totalSecondsClaimedX128,
                key.startTime,
                key.endTime,
                liquidity,
                secondsPerLiquidityInsideInitialX128,
                secondsPerLiquidityInsideX128,
                block.timestamp
            );

        // if this overflows, e.g. after 2^32-1 full liquidity seconds have been claimed,
        // reward rate will fall drastically so it's safe
        incentive.totalSecondsClaimedX128 += secondsInsideX128;
        // reward is never greater than total reward unclaimed
        incentive.totalRewardUnclaimed -= reward;
        // this only overflows if a token has a total supply greater than type(uint256).max
        rewards[key.rewardToken][deposit.owner] += reward;

        Stake storage stake = _stakes[tokenId][incentiveId];
        delete stake.secondsPerLiquidityInsideInitialX128;
        delete stake.liquidityNoOverflow;
        if (liquidity >= type(uint96).max) delete stake.liquidityIfOverflow;
        emit TokenUnstaked(tokenId, incentiveId);
    }

    function claimReward(
        IER20Minimal rewardToken,
        address to,
        uint256 amountRequested
    ) external override returns (uint256 reward) {
        reward = rewards[rewardToken][msg.sender];
        if (amountRequested != 0 && amountRequested < reward) {
            reward = amountRequested;
        }
        rewards[rewardToken][msg.sender] -= reward;
        TransferHelper.safeTransfer(address(rewardToken), to, reward);

        emit RewardClaimed(to, reward);
    }

    function getRewardInfo(IncentiveKey memory key, uint256 tokenId)
        external
        view
        override
        returns (uint256 reward, uint160 secondsInsideX128)
    {
        bytes32 incentiveId = IncentiveId.compute(key);

        (
            uint160 secondsPerLiquidityInsideInitialX128,
            uint128 liquidity
        ) = stakes(tokenId, incentiveId);
        require(
            liquidity > 0,
            "UniswapV3Staker::getRewardInfo: stake does not exist"
        );

        Deposit memory deposit = deposits[tokenId];
        Incentive memory incentive = incentives[incentiveId];

        (, uint160 secondsPerLiquidityInsideX128, ) = key
            .pool
            .snapshotCumulativesInside(deposit.tickLower, deposit.tickUpper);

        (reward, secondsInsideX128) = RewardMath.computeRewardAmount(
            incentive.totalRewardUnclaimed,
            incentive.totalSecondsClaimedX128,
            key.startTime,
            key.endTime,
            liquidity,
            secondsPerLiquidityInsideInitialX128,
            secondsPerLiquidityInsideX128,
            block.timestamp
        );
    }

    ///@notice Upon receiving a Uniswap V3 ERC721 ,creates the token deposit setting owner to 'from'.Also stakes token
    /// in one or more incentives if properly formatted 'data' has a length >0.
    /// @inheritdoc IERC721Receiver

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        require(
            msg.sender == address(nonfungiblePositionManager),
            "UniswapV3Staker :: onERC721Received : not a univ3 nft"
        );
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickerUpper,
            ,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.position(tokenId);
        deposits[tokenId] = Deposit({
            owner: from,
            numberOfLockes: 0,
            tickLower: tickLower,
            tickUpper: tickUpper
        });

        emit DepositTransferred(tokenId, address(0), from);

        if (data.length > 0) {
            if (data.length == 160) {
                _stakeToken(abi.decode(data, (IncentiveKey)), tokenId);
            } else {
                IncentiveKey[] memory keys = abi.decode(data, (IncentiveKey[]));
                for (uint256 i = 0; i < keys.length; i++) {
                    _stakeToken(keys[i], tokenId);
                }
            }
        }

        return this.onERC721Received.selector;
    }

    ///@inheritdoc IUniswapV3Vaulter
    function transferDeposit(uint256 tokenId, address to) external override {
        require(
            to != address(0),
            "UniswapV3Vaulter::transferDeposit : invalid transfer recipient"
        );
        address owner = deposits[tokenId].owner;
        require(
            owner == msg.sender,
            "UniswapV3Vaulter::transferDeposit : can only be called by deposit owner"
        );
        deposits[tokenId].owner = to;
        emit DepositTransferred(tokenId, owner, to);
    }

    /// @inheritdoc IUniswapV3Vaulter
    function withdrawToken(
        uint256 tokenId,
        address to,
        bytes memory data
    ) external override {
        require(
            to != address(this),
            "UniswapV3Staker::withdrawToken: cannot withdraw to staker"
        );
        Deposit memory deposit = deposits[tokenId];
        require(
            deposit.numberOfStakes == 0,
            "UniswapV3Staker::withdrawToken: cannot withdraw token while staked"
        );
        require(
            deposit.owner == msg.sender,
            "UniswapV3Staker::withdrawToken: only owner can withdraw token"
        );

        delete deposits[tokenId];
        emit DepositTransferred(tokenId, deposit.owner, address(0));

        nonfungiblePositionManager.safeTransferFrom(
            address(this),
            to,
            tokenId,
            data
        );
    }

    ///@dev Stakes a deposited token without doing an ownership check
    function _stakeToken(IncentiveKey memory key, uint256 tokenId) private {
        require(block.timestamp >= key.startTime, "incentive not started");
        require(block.timestamp < key.endTime, "incentive ended");

        bytes32 incentiveId = IncentiveId.compute(key);

        (
            IUniswapV3Pool pool,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        ) = NFTPositionInfo.getPositionInfo(
                factory,
                nonfungiblePositionManager,
                tokenId
            );

        require(
            pool == key.pool,
            "UniswapV3Vaulter::stakeToken: token pool is not the incentive pool"
        );
        require(
            liquidity > 0,
            "UniswapV3Vaulter::stakeToken: cannot stake token with 0 liquidity"
        );

        deposits[tokenId].numberOfLockes++;
        incentives[incentiveId].numberOfLockes++;
        (, uint160 secondsPerLiquidityInsideX128, ) = pool
            .snapshotCumulativesInside(tickLower, tickUpper);
    }
}
