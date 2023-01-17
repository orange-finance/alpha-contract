import env from "hardhat";

export const getAddresses = () => {
  switch (env.network.name) {
    case "goerli":
      return {
        Deployer: "0xe66ffFd2D3aDE2697B3Cbeb69877a1fFE8A1f275",
        UniswapFactory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        Weth: "0x6E8EDc17Ef3db5f3Fbb7B8f6574934bD169E22E7",
        Usdc: "0xCc0a1e7086eD38a701dD8886C1AaAc1CC00dF71f",
        AavePool: "0x1Fe749bef290c350e85cC7BF29B228344355E52D",
        VDebtWeth: "0x2Bb51435e2fd8d5FA43ef5287821D01faA01f1f8",
        AUsdc: "0xe822F2c0AF9be5B11EDeEd50e617B572567b67E0",
        UniswapPool: "0x5D5c8Aa7E4Df82D5f5e33b77c39524EBbc8988bF",
        OrangeAlphaVault: "0x65B95573B3d757cDE0678E38987F5557E5020845",

        // AavePool: "0x76F3b1DB35040D231245a039fC67561CF4b85953",
        // VDebtWeth: "0x3B395ECbDf98c18AE09d1f6e6e5B8f8Fe292912e",
        // AUsdc: "0x9235951345d89eD5508bd837AD9dA1c9BeDC107C",
        // OrangeAlphaVault: "0x3127EB9C5e880dA5C29D3bB71Dd4C36dC5ba62E4",
        // OrangeAlphaVault: "0xc02F438122c1A3c001526949ee4dEc6c58D0Ff06",
        // OrangeAlphaVault: "0x8A5FFE856A9a42d88ea23e1d93c7fC3bAE6d831b",
        // OrangeAlphaVault: "0xb56B1014068cE88b70bEC6661c6832fB1DaAB666",
        // OrangeAlphaVault: "0x25540ac2015a2Fb4993C752F0d57c91821D83713", //deposit時のemitAction eventなし
        UniswapV3PoolAccessorMock: "0xABEcB921FbA87F8157dD7c070FF797352f38Ee79",
        LiquidityAmountsMock: "0x884B0F4c8c23D4d8Fd095B24879aaE6461b32475",
        GelatoMock: "0x12FD9A329DDad7a71Ec769Aa11225C8EAC5EbCD1",
      };
  }
};
