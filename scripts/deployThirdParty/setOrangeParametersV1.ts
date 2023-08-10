import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeParametersV1 } from "../../typechain-types/contracts/coreV1";

async function main() {
  const a = getAddresses()!;

  const params = (await ethers.getContractAt(
    "OrangeParametersV1",
    "0xEB5b8C7f73053Ee5b544684c63DD39AFf05B065d"
  )) as OrangeParametersV1;

  const tx4 = await params.setHelper(
    "0x1A5f00303750a301f3Fd491C9915C65370b837C5"
  );
  console.log(tx4);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
