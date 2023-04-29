import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeAlphaParameters } from "../../typechain-types/contracts/core";

async function main() {
  const a = getAddresses()!;

  const params = (await ethers.getContractAt(
    "OrangeAlphaParameters",
    a.OrangeAlphaParameters
  )) as OrangeAlphaParameters;

  const tx = await params.setDepositCap(250_000_000_000, 250_000_000_000);
  console.log(tx);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
