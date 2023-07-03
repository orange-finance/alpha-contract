import env from "hardhat";

export const getAddresses = () => {
  switch (env.network.name) {
    case "goerli":
      return {
        Deployer: "0xe66ffFd2D3aDE2697B3Cbeb69877a1fFE8A1f275",
        UniswapFactory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        // Weth: "0x6E8EDc17Ef3db5f3Fbb7B8f6574934bD169E22E7",
        // Usdc: "0xCc0a1e7086eD38a701dD8886C1AaAc1CC00dF71f",
        // AavePool: "0x1Fe749bef290c350e85cC7BF29B228344355E52D",
        // VDebtWeth: "0x2Bb51435e2fd8d5FA43ef5287821D01faA01f1f8",
        // AUsdc: "0xe822F2c0AF9be5B11EDeEd50e617B572567b67E0",
        // UniswapPool: "0x5D5c8Aa7E4Df82D5f5e33b77c39524EBbc8988bF",
        // OrangeAlphaVault: "0x65b0661C10eA4beC7Dd9EbF578e6B6ac27b6f82F",
        // UniswapV3PoolAccessorMock: "0xABEcB921FbA87F8157dD7c070FF797352f38Ee79",
        LiquidityAmountsMock: "0x884B0F4c8c23D4d8Fd095B24879aaE6461b32475",
        // GelatoMock: "0x2461B62c06500C0256c324f57d4b71F9A5557e16",
        Weth: "0x246ce443416fd4cc9C057C99cA0918F4d3d525d4",
        Usdc: "0xc24e97F0B049C6D1EC2Ddb21f2f55C128f74412c",
        AavePool: "0x0a4eDC8A76776468311F3f58a6B6cf4c3DC6e287",
        VDebtWeth: "0x0d63c72e6F356f42D1940352F6eDD4f983E54CaD",
        AUsdc: "0x71c5271dCda234A1acA574f490C87e087A108E71",
        // UniswapPool: "0x566C69144Cfa02d0406635844488dD5BCF7c52a0", // 0.3%
        UniswapPool: "0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443", // 0.05%
        UniswapV3PoolAccessorMock: "0xF195B1Df7c20a4F266366dE4Fc3e95cD40d717bF",
        OrangeAlphaVault: "0x863EE7dBc5F96e1c91aB94914194c21cD7A2eEd6",
      };
    case "arb":
      return {
        Deployer: "0xe66ffFd2D3aDE2697B3Cbeb69877a1fFE8A1f275",
        Owner: "0x38E4157345Bd2c8Cf7Dbe4B0C75302c2038AB7Ec", //Safe
        Strategist: "0xd31583735e47206e9af728EF4f44f62B20db4b27",
        GelatoDedicatedMsgSender: "0xBa568F558aB731Aaa88272CF2206CBFc9611671C",
        Weth: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        Usdc: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        AavePool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
        VDebtWeth: "0x0c84331e39d6658Cd6e6b9ba04736cC4c4734351",
        AUsdc: "0x625E7708f30cA75bfd92586e17077590C60eb4cD",
        UniswapPool: "0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443", // 0.05%
        UniswapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        Balancer: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",
        CamelotWethUsdcePoolAddr: "0x521aa84ab3fcc4c05cABaC24Dc3682339887B126",
        //libraries
        GelatoOps: "0xadFf2D91Cc75C63e1A1bb882cFa9EB2b421a1B52",
        SafeAavePool: "0xc370958Be186aC4a3cA50B897311Fd13490796fa",
        UniswapV3Twap: "0x9E58899B29361085Dc60EA4596650572f96F1Fc2",
        RebalancePositionComputer: "0x180240fee8FA687212f98b707f8D89be9EEDDBDF",
        //core contracts
        OrangeAlphaParameters: "0xB4F003bcccD9514CbA2a40e26CA9e275c93EAC6C",
        OrangeAlphaVault: "0x1c99416c7243563ebEDCBEd91ec8532fF74B9a39",
        OrangeAlphaPeriphery: "0xCa612E6bCDcCa3d1b9828FDc912643228D4b8AA9",
        OrangeAlphaResolver: "0x1Cd946d26286598B344D41260a65C51755A099F9",
        OrangeAlphaComputer: "0x6D9E5F6Eb48f1cd809c32AaBfE58A5da54029700",
        //delta neutral
        // OrangeDeltaParameters: "0x1eCaB7f39B7A1165BDCD9272d42244F8e0AD4aBe",
        OrangeDeltaParameters: "0x153FD22940BDA400AB4B51860E18319D9d3EC3fF",
        OrangeDeltaVault: "0x810fd69F58fF7Ff8553D43a5D3DCE3853960cAa6",
        OrangeDeltaPeriphery: "0x2611D4aB59308Fe608F662aC993A7EC7b2647266",
        OrangeDeltaResolver: "0x5ee552490E81582a734f234BfAce3D24Abdba043",
        OrangeDeltaComputer: "0x75aaa778C7e6cAb08dc94452DaDe7909F8Aa7bf5",
        //v1
        OrangeParametersV1: "0xB5101c45109D7ECE0d3357f161FA0c2b66599b77",
        OrangeVaultV1: "0x5af9A292Aec0acab889138d1bDD50630aF8FF51D",
        // OrangeStrategyImplV1: "0xCEd0Df830B3C8d3CccE8F9271D50caE5bF04D051",
        OrangeStrategyHelperV1: "0xFC60b4Fe576d199138b77bd513936f45C6030E8B",
        OrangeEmitter: "0xaCD36B472ca6cF2E167CB8feA751B33e45b432D9",
        //v1 for camelot usdc.e/weth
        OrangeParametersV1CamelotUsdceWeth:
          "0xB6B552Fc1a890B792d0F9bC0667888B7035f92F7",
        CamelotV3LiquidityPoolManagerUsdceWeth:
          "0x767901B7D185bb951C7DA20cf55ae1F681953217",
        AaveLendingPoolManagerCamelotUsdceWeth:
          "0xe5b174F0A74986172404414CD7a13e833451Be3D",
        OrangeVaultV1CamelotUsdceWeth:
          "0xB9c5425084671221d7D5A547dBf1Bdcec26C8B7d",
        OrangeStrategyImplV1: "0x0E7c98AA52311F36b637Cfc75723435737929597",
        OrangeStrategyHelperV1CamelotUsdceWeth:
          "0x1ba8fE85592aE22F523765492E1D7Fb1D1534359",
      };
  }
};
