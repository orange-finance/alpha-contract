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

  const tx = await params.setPeriphery(a.OrangeDeltaPeriphery);
  console.log(tx);

  const tx2 = await params.setDepositCap(350000000000, 350000000000);
  console.log(tx2);

  const tx3 = await params.setGelato(a.Owner);
  console.log(tx3);

  const tx4 = await params.setStrategist(a.Strategist, true);
  console.log(tx4);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
