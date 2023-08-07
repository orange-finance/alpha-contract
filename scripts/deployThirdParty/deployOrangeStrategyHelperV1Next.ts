import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  await Deploy(
    "OrangeStrategyHelperV1Next",
    "0x6d9d02c8CE73a239AC87Df96E7b881c1521F5531"
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
