import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;
  // const lib = await Deploy("RebalancePositionComputer");

  await DeployLibraries(
    "OrangeAlphaComputer",
    { RebalancePositionComputer: a.RebalancePositionComputer },
    a.OrangeDeltaVault,
    a.OrangeDeltaParameters
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
