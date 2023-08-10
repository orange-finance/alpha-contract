import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeStrategyHelperV1 } from "../../typechain-types/contracts/coreV1";

async function main() {
  const a = getAddresses()!;

  const helper = (await ethers.getContractAt(
    "OrangeStrategyHelperV1Next",
    "0x1A5f00303750a301f3Fd491C9915C65370b837C5"
  )) as OrangeStrategyHelperV1Next;

  const tx = await helper.setStrategist(a.Strategist, true);
  console.log(tx);

  const tx2 = await helper.setStrategist(a.GelatoDedicatedMsgSender, true);
  console.log(tx2);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
