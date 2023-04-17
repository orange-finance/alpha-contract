import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeAlphaParameters } from "../../typechain-types/contracts/core/";

async function main() {
  const a = getAddresses()!;

  const params = (await ethers.getContractAt(
    "OrangeAlphaParameters",
    a.OrangeAlphaParameters
  )) as OrangeAlphaParameters;

  // params.setPeriphery(address(periphery));
  const tx = await params.setPeriphery(a.OrangeAlphaPeriphery);
  console.log(tx);

  // params.setAllowlistEnabled(false);
  const tx2 = await params.setAllowlistEnabled(false);
  console.log(tx2);

  //lockup
  const tx3 = await params.setLockupPeriod(0);
  console.log(tx3);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
