import { ethers } from "hardhat";
import { Deploy, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "OrangeAlphaVault",
  decimals: 6,
};

const lowerTick = -205680;
const upperTick = -203760;

async function deployOrangeAlphaVault(poolAddr: string, aaveAddr: string) {
  await Deploy(
    "OrangeAlphaVault",
    vaultMeta.name,
    vaultMeta.symbol,
    poolAddr,
    aaveAddr,
    lowerTick,
    upperTick
  );
}

async function main() {
  const a = getAddresses()!;
  await deployOrangeAlphaVault(a.UniswapPool, a.AavePool);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
