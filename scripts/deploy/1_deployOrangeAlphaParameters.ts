import { ethers } from "hardhat";
import { Deploy, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

async function deployOrangeAlphaParameters() {
  await Deploy("OrangeAlphaParameters");
}

async function main() {
  await deployOrangeAlphaParameters();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
