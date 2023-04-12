import { ethers } from "hardhat";
import { Deploy, DeployLibraries, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "OrangeAlphaVault",
  decimals: 6,
};

async function main() {
  const a = getAddresses()!;
  await DeployLibraries(
    "OrangeAlphaVault",
    { SafeAavePool: a.SafeAavePool },
    vaultMeta.name,
    vaultMeta.symbol,
    a.UniswapPool,
    a.Weth,
    a.Usdc,
    a.UniswapRouter,
    a.AavePool,
    a.VDebtWeth,
    a.AUsdc,
    a.OrangeAlphaParameters
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
