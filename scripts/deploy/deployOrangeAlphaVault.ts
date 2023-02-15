import { ethers } from "hardhat";
import { Deploy, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";
import { IUniswapV3PoolDerivedState__factory } from "../../typechain-types";

const vaultMeta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "OrangeAlphaVault",
  decimals: 6,
};

const lowerTick = -205620;
const upperTick = -203820;
const stoplossLowerTick = -206280;
const stoplossUpperTick = -203160;

async function deployOrangeAlphaVault(
  poolAddr: string,
  wethAddr: string,
  usdcAddr: string,
  aaveAddr: string,
  vDebtWethAddr: string,
  aUsdcAddr: string
) {
  const vault = await Deploy(
    "OrangeAlphaVault",
    vaultMeta.name,
    vaultMeta.symbol,
    vaultMeta.decimals,
    poolAddr,
    wethAddr,
    usdcAddr,
    aaveAddr,
    vDebtWethAddr,
    aUsdcAddr
  );
  // vault.setTicks(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick);
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
