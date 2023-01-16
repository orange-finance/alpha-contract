import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";

const NormalizedIncome = BigNumber.from("2600000000000000000"); //26 * 1e17
const NormalizedVariableDebt = BigNumber.from("3250000000000000000"); //325 * 1e16

async function deployAavePool(wethAddr: string, usdcAddr: string) {
  let tx;
  let receipt;

  // AaveV3Pool
  const pool = await Deploy("AaveV3PoolMock");

  // Set Weth
  tx = await pool.deployAssets(
    wethAddr,
    NormalizedIncome,
    NormalizedVariableDebt
  );
  receipt = await tx.wait();
  console.log('VDebtWeth: "' + receipt.events![0].args![1] + '",');

  // Set Usdc
  tx = await pool.deployAssets(
    usdcAddr,
    NormalizedIncome,
    NormalizedVariableDebt
  );
  receipt = await tx.wait();
  console.log('AUsdc: "' + receipt.events![0].args![0] + '",');
}

async function main() {
  const a = getAddresses()!;
  await deployAavePool(a.Weth, a.Usdc);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
