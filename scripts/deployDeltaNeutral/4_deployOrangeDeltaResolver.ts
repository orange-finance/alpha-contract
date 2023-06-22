import { ethers } from "hardhat";
import { DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;

  await DeployLibraries(
    "OrangeAlphaResolver",
    { UniswapV3Twap: a.UniswapV3Twap },
    a.OrangeDeltaVault,
    a.OrangeDeltaParameters
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
