import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

async function deployOrangeAlphaParameters() {
  // const gelatoOps = await Deploy("GelatoOps");
  const a = getAddresses()!;

  await DeployLibraries("OrangeAlphaParameters", {
    GelatoOps: a.GelatoOps,
  });
}

async function main() {
  await deployOrangeAlphaParameters();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
