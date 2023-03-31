import { ethers } from "hardhat";
import { Deploy, DeployLibraries, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "OrangeAlphaVault",
  decimals: 6,
};

async function deployOrangeAlphaVault(
  poolAddr: string,
  wethAddr: string,
  usdcAddr: string,
  aaveAddr: string,
  vDebtWethAddr: string,
  aUsdcAddr: string,
  orangeAlphaParametersAddr: string
) {
  const safeAavePool = await Deploy("SafeAavePool");

  await DeployLibraries(
    "OrangeAlphaVault",
    { SafeAavePool: safeAavePool.address },
    vaultMeta.name,
    vaultMeta.symbol,
    poolAddr,
    wethAddr,
    usdcAddr,
    aaveAddr,
    vDebtWethAddr,
    aUsdcAddr,
    orangeAlphaParametersAddr
  );
}

async function main() {
  const a = getAddresses()!;
  await deployOrangeAlphaVault(
    a.UniswapPool,
    a.Weth,
    a.Usdc,
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
