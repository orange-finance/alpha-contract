import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;
  await Deploy("OrangeStrategyHelperV1", a.OrangeVaultV1CamelotUsdceWeth);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
