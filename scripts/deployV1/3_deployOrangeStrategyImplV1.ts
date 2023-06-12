import { ethers } from "hardhat";
import { Deploy, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;
  await Deploy("OrangeStrategyImplV1");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
