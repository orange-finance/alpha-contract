import { ethers } from "hardhat";
import { Verify, VerifyLibraries } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;

  await VerifyLibraries(
    a.OrangeAlphaComputer,
    {
      RebalancePositionComputer: a.RebalancePositionComputer,
    },
    [a.OrangeAlphaVault, a.OrangeAlphaParameters]
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
