import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  // await Deploy("GelatoOps");
  // await Deploy("SafeAavePool");
  // await Deploy("UniswapV3Twap");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
