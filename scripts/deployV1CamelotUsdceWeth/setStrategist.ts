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
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
