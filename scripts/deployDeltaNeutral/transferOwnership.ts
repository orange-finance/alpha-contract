import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeAlphaParameters } from "../../typechain-types/contracts/core";

async function main() {
  const a = getAddresses()!;

  const params = (await ethers.getContractAt(
    "OrangeAlphaParameters",
    a.OrangeDeltaParameters
  )) as OrangeAlphaParameters;

  const tx = await params.transferOwnership(a.Owner);
  console.log(tx);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
