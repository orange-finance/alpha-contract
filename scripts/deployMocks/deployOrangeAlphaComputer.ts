import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;
  const lib = await Deploy("RebalancePositionComputer");

  await DeployLibraries(
    "OrangeAlphaComputer",
    { RebalancePositionComputer: lib.address },
    a.OrangeAlphaVault,
    a.OrangeAlphaParameters
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
