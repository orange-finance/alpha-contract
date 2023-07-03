import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeStrategyHelperV1 } from "../../typechain-types/contracts/coreV1";

async function main() {
  const a = getAddresses()!;

  const helper = (await ethers.getContractAt(
    "OrangeStrategyHelperV1",
    a.OrangeStrategyHelperV1CamelotUsdceWeth
  )) as OrangeStrategyHelperV1;

  const tx = await helper.setStrategist(a.Strategist, true);
  console.log(tx);

  const tx2 = await helper.setStrategist(a.GelatoDedicatedMsgSender, true);
  console.log(tx2);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
