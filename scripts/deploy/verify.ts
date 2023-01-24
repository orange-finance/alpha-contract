import { ethers } from "hardhat";
import { Verify, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "OrangeAlphaVault",
  decimals: 6,
};

const lowerTick = -205680;
const upperTick = -203760;

const verify = async () => {
  const a = getAddresses()!;
  await Verify(a.OrangeAlphaVault, [
    vaultMeta.name,
    vaultMeta.symbol,
    vaultMeta.decimals,
    a.UniswapPool,
    a.Weth,
    a.Usdc,
    a.AavePool,
    a.VDebtWeth,
    a.AUsdc,
    lowerTick,
    upperTick,
  ]);
};

const main = async () => {
  await verify();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
