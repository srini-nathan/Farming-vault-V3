//hardhat.config.js

require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
const Rinkeby_RPC_Url ="https://eth-rinkeby.alchemyapi.io/v2/SvPJSSgBwaepMghEoVACV32CCufbohKH";
const privateKey = "f4bb548245b536a4e610b53b6f8c79fb5f5443428087fdd532eee18e3bf81711";
module.exports ={
    solidity:"0.8.4",
    defaultNetwork:"rinkeby",
    networks:{
        rinkeby:{
            url:Rinkeby_RPC_Url,
            account:[privateKey]
        }
    }

}
