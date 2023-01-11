import env from "hardhat";

export const getAddresses = () => {
  switch (env.network.name) {
    // case "goerli":
    //   return {
    //     Usdc: "0x160601681F7CFD8874f4DE38bE928284A6AAdd61",
    //     Usdt: "0x591d66AD81984bF44f26Afa2dBBF9794cC91Df0C",
    //     Susd: "0x37C05eb4310E4e0ef9C2806fE899b7df6A514147",
    //     AaveV3Pool: "0xd3D29bd93346a8Ea455c71c8B8e355282f33F30F",
    //     AUsdc: "0x07993Df0C325A7E8D6824696ddB733fE08Ad96b0",
    //     ASusd: "0xE1A41E10ec5A188127879aD683AB4eC425149C89",
    //     VDebtSusd: "0x4ba3FD4392AC45CDBA2e8F0F27f01cB00C65b1D6",
    //     SDebtSusd: "0xdbd9A7c0E28631473B77b0328ED1C1B673e42693",
    //     OpToken: "0xf40F8E136c2325C33d704A96Eaf48f982323E030",
    //     AaveV3Reward: "0xdB9b17EcfDE8fc86B50643De9dF73F8A5dB856F6",
    //     ChainlinkUsdc: "0xDFE48Fe31c5bCc6f502eeCBcC5f35C409D3B7FF9",
    //     ChainlinkSusd: "0x6c51ABbd4E7DDF71b03Ff7c319ecA5da7A9774F7",
    //   } as AddressesProtocols;

    default:
      return {};
  }
};
