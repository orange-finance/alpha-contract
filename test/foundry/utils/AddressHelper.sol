// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

library AddressHelper {
    uint256 constant MAINNET_ID = 1;
    uint256 constant GOERLI_ID = 5;
    uint256 constant ARB_ID = 42161;

    struct TokenAddr {
        address wethAddr;
        address usdcAddr;
        address daiAddr;
    }
    struct AaveAddr {
        address poolAddr;
        address aaveOracleAddr;
        address ausdcAddr;
        address vDebtUsdcAddr;
        address sDebtUsdcAddr;
        address awethAddr;
        address vDebtWethAddr;
        address sDebtWethAddr;
    }
    struct UniswapAddr {
        address wethUsdcPoolAddr;
        address wethUsdcPoolAddr500;
        address routerAddr;
        address nonfungiblePositionManagerAddr;
        address arbUsdcePoolAddr;
    }

    function addresses(
        uint256 _chainid
    ) internal pure returns (TokenAddr memory tokenAddr_, AaveAddr memory aaveAddr_, UniswapAddr memory uniswapAddr_) {
        if (_chainid == MAINNET_ID) {
            //mainnet
            tokenAddr_ = TokenAddr({
                wethAddr: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                usdcAddr: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
                daiAddr: address(0)
            });
            aaveAddr_ = AaveAddr({
                poolAddr: address(0),
                aaveOracleAddr: address(0),
                ausdcAddr: address(0),
                vDebtUsdcAddr: address(0),
                sDebtUsdcAddr: address(0),
                awethAddr: address(0),
                vDebtWethAddr: address(0),
                sDebtWethAddr: address(0)
            });
            uniswapAddr_ = UniswapAddr({
                wethUsdcPoolAddr: address(0),
                wethUsdcPoolAddr500: address(0),
                routerAddr: address(0),
                nonfungiblePositionManagerAddr: address(0),
                arbUsdcePoolAddr: address(0)
            });
        } else if (_chainid == GOERLI_ID) {
            //goerli
            tokenAddr_ = TokenAddr({
                wethAddr: 0x6E8EDc17Ef3db5f3Fbb7B8f6574934bD169E22E7,
                usdcAddr: 0xCc0a1e7086eD38a701dD8886C1AaAc1CC00dF71f,
                daiAddr: address(0)
            });
            aaveAddr_ = AaveAddr({
                poolAddr: address(0),
                aaveOracleAddr: address(0),
                ausdcAddr: address(0),
                vDebtUsdcAddr: address(0),
                sDebtUsdcAddr: address(0),
                awethAddr: address(0),
                vDebtWethAddr: address(0),
                sDebtWethAddr: address(0)
            });
            uniswapAddr_ = UniswapAddr({
                wethUsdcPoolAddr: 0x5D5c8Aa7E4Df82D5f5e33b77c39524EBbc8988bF,
                wethUsdcPoolAddr500: address(0),
                routerAddr: address(0),
                nonfungiblePositionManagerAddr: address(0),
                arbUsdcePoolAddr: address(0)
            });
        } else if (_chainid == ARB_ID) {
            //arbitrum
            tokenAddr_ = TokenAddr({
                wethAddr: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
                usdcAddr: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, //USDC.e
                daiAddr: address(0)
            });
            aaveAddr_ = AaveAddr({
                poolAddr: 0x794a61358D6845594F94dc1DB02A252b5b4814aD,
                aaveOracleAddr: 0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7,
                ausdcAddr: 0x625E7708f30cA75bfd92586e17077590C60eb4cD,
                vDebtUsdcAddr: 0xFCCf3cAbbe80101232d343252614b6A3eE81C989,
                sDebtUsdcAddr: 0x307ffe186F84a3bc2613D1eA417A5737D69A7007,
                awethAddr: 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8,
                vDebtWethAddr: 0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351,
                sDebtWethAddr: 0xD8Ad37849950903571df17049516a5CD4cbE55F6
            });
            uniswapAddr_ = UniswapAddr({
                wethUsdcPoolAddr: 0x17c14D2c404D167802b16C450d3c99F88F2c4F4d, // 0.3%
                wethUsdcPoolAddr500: 0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443, // 0.05%
                routerAddr: 0xE592427A0AEce92De3Edee1F18E0157C05861564,
                nonfungiblePositionManagerAddr: 0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
                arbUsdcePoolAddr: 0xcDa53B1F66614552F834cEeF361A8D12a0B8DaD8 // 0,05%
            });
        }
    }
}

library AddressHelperV1 {
    uint256 constant ARB_ID = 42161;

    struct BalancerAddr {
        address vaultAddr;
    }

    function addresses(uint256 _chainid) internal pure returns (BalancerAddr memory balancerAddr_) {
        if (_chainid == ARB_ID) {
            balancerAddr_ = BalancerAddr({vaultAddr: 0xBA12222222228d8Ba445958a75a0704d566BF2C8});
        }
    }
}

library AddressHelperV2 {
    uint256 constant ARB_ID = 42161;

    struct TokenAddrV2 {
        address usdcAddr;
        address arbAddr;
    }
    struct CamelotAddr {
        address wethUsdcPoolAddr;
        address wethUsdcePoolAddr;
        address wethUsdceDataStorageAddr;
        address arbUsdcePoolAddr;
    }

    function addresses(
        uint256 _chainid
    ) internal pure returns (TokenAddrV2 memory tokenAddrV2_, CamelotAddr memory camelotAddr_) {
        if (_chainid == ARB_ID) {
            tokenAddrV2_ = TokenAddrV2({
                usdcAddr: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831, //USDC (not USDC.e)
                arbAddr: 0x912CE59144191C1204E64559FE8253a0e49E6548
            });
            camelotAddr_ = CamelotAddr({
                wethUsdcPoolAddr: 0xB1026b8e7276e7AC75410F1fcbbe21796e8f7526,
                wethUsdcePoolAddr: 0x521aa84ab3fcc4c05cABaC24Dc3682339887B126,
                wethUsdceDataStorageAddr: 0x6c70EC64217CfE81A7961168CE9909ebAd7C2935,
                arbUsdcePoolAddr: 0x4E635D35bB02576d0eAb75eF5E7EBE61C12F3C76
            });
        }
    }
}
