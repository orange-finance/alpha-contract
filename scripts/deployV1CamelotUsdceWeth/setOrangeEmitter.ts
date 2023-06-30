import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeEmitter } from "../../typechain-types/contracts/coreV1";

async function main() {
  const a = getAddresses()!;
  const emitter = (await ethers.getContractAt(
    "OrangeEmitter",
    a.OrangeEmitter
  )) as OrangeEmitter;

  const tx2 = await emitter.pushVaultV1(a.OrangeVaultV1CamelotUsdceWeth);
  console.log(tx2);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
