
// pragma solidity ^0.8.4;

// contract TransparentAdminUpgradeableProxy {
//     address implementation;
//     address admin;

//     fallback() external payable{
//         require(msg.sender != admin);
//         implementation.delegatecall.value(msg.value)(msg.data);
//     }

//     function upgrade(address newImplementation) external{
//         if(msg.sender != admin) fallback();
//         implementation = newImplementation;
//     }
// }
