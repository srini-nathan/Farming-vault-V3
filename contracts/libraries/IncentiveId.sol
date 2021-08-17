// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.4;
import "../interfaces/IUniswapV3Vault.sol";

library IncentiveId {
    ///@notice Calculate the key for a staking incentive
    ///@param key The components used to compute the incentive identifier
    ///@return incentiveId The identifier for the incentive

    function compute(IUniswapV3Vaulter.IncentiveKey memory key)
        internal
        pure
        returns (bytes32 incentiveId)
    {
        return keccak256(abi.encode(key));
    }
}
