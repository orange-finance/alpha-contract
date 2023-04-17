import { ethers } from "hardhat";
import { Verify, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "OrangeAlphaVault",
  decimals: 6,
};

const verify = async () => {
  const a = getAddresses()!;

  // await Verify(a.OrangeAlphaParameters, []);

  await Verify(a.OrangeAlphaVault, [
    vaultMeta.name,
    vaultMeta.symbol,
    a.UniswapPool,
    a.Weth,
    a.Usdc,
    a.UniswapRouter,
    a.AavePool,
    a.VDebtWeth,
    a.AUsdc,
    a.OrangeAlphaParameters,
  ]);

  await Verify(a.OrangeAlphaPeriphery, [
    a.OrangeAlphaVault,
    a.OrangeAlphaParameters,
  ]);

  // await Verify(a.OrangeAlphaResolver, [
  //   a.OrangeAlphaVault,
  //   a.OrangeAlphaParameters,
  // ]);
};

const main = async () => {
  await verify();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
