import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeEmitter } from "../../typechain-types/contracts/coreV1";

async function main() {
  const a = getAddresses()!;

  const pool = (await ethers.getContractAt(
    "UniswapV3LiquidityPoolManager",
    a.UniswapV3LiquidityPoolManager
  )) as UniswapV3LiquidityPoolManager;

  const tx = await pool.setVault(a.OrangeVaultV1);
  console.log(tx);

  const lending = (await ethers.getContractAt(
    "AaveLendingPoolManager",
    a.AaveLendingPoolManager
  )) as AaveLendingPoolManager;

  const tx2 = await lending.setVault(a.OrangeVaultV1);
  console.log(tx2);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
