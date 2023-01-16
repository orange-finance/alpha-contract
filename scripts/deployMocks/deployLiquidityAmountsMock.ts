import { ethers } from "hardhat";
import { Deploy, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

async function deployLiquidityAmountsMock() {
  await Deploy("LiquidityAmountsMock");
}

async function main() {
  const a = getAddresses()!;
  await deployLiquidityAmountsMock();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
