import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;
  await Deploy("OrangeStrategyHelperV1", a.OrangeVaultV1);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
