import { ethers } from "hardhat";
import { Deploy, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "OrangeAlphaVault",
  decimals: 6,
};

const lowerTick = -202400;
const upperTick = -201800;

async function deployOrangeAlphaVault(
  poolAddr: string,
  wethAddr: string,
  usdcAddr: string,
  aaveAddr: string,
  vDebtWethAddr: string,
  aUsdcAddr: string
) {
  await Deploy(
    "OrangeAlphaVault",
    vaultMeta.name,
    vaultMeta.symbol,
    vaultMeta.decimals,
    poolAddr,
    wethAddr,
    usdcAddr,
    aaveAddr,
    vDebtWethAddr,
    aUsdcAddr,
    lowerTick,
    upperTick
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
    a.AUsdc
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
