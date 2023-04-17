import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;
  await DeployLibraries("OrangeAlphaParameters", {
    GelatoOps: a.GelatoOps,
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
