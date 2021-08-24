//SPDX-License-Identifier:MIT
pragma solidity ^0.8.4;

import "./PlethoriVaultA.sol";
import "./PlethoriVaultB.sol";
import "./PlethoriVaultC.sol";
import "./interfaces/IERC20.sol";

contract VaultControl {
    address public rewardToken;
    address public plethoriVaultA;
    address public plethoriVaultB;
    address public plethoriVaultC;
    uint256 private RATE_A = 3000;
    uint256 private RATE_B = 2500;
    uint256 private RATE_C = 4500;
    address public admin;

    enum Side {
        A,
        B,
        C
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "The caller is not admin.");
        _;
    }

    constructor(
        address _rewardToken,
        address _plethoriVaultA,
        address _plethoriVaultB,
        address _plethoriVaultC
    ) {
        rewardToken = _rewardToken;
        plethoriVaultA = _plethoriVaultA;
        plethoriVaultB = _plethoriVaultB;
        plethoriVaultC = _plethoriVaultC;
    }

    function getBalance() internal view returns (uint256) {
        return IERC20(rewardToken).balanceOf(address(this));
    }

    /** @notice distribute reward token function
     *
     */

    function distributeRewardToken() external onlyAdmin {
        uint256 balance = getBalance();
        require(balance != 0, "The reward token balance is zero!");

        uint256 amountA = (balance * RATE_A) / 1e4;
        uint256 amountB = (balance * RATE_B) / 1e4;
        uint256 amountC = (balance * RATE_C) / 1e4;

        require(
            IERC20(rewardToken).transfer(plethoriVaultA, amountA),
            "Could not transfer tokens."
        );
        require(
            IERC20(rewardToken).transfer(plethoriVaultB, amountB),
            "Could not transfer tokens."
        );

        require(
            IERC20(rewardToken).transfer(plethoriVaultC, amountC),
            "Could not transfer tokens."
        );
    }

    function distributeRestToken(Side side, uint256 amount) external onlyAdmin {
        uint256 balance = getBalance();
        require(balance != 0, "Can not zero amount");
        require(amount != 0, "Can not zero");
        require(balance >= amount, "The amount is not over than balance");

        if (side == Side.A) {
            require(
                IERC20(rewardToken).transfer(plethoriVaultA, amount),
                "Could not transfer tokens."
            );
        } else if (side == Side.B) {
            require(
                IERC20(rewardToken).transfer(plethoriVaultB, amount),
                "Could not transfer tokens."
            );
        } else {
            require(
                IERC20(rewardToken).transfer(plethoriVaultC, amount),
                "Could not transfer tokens."
            );
        }
    }
}
