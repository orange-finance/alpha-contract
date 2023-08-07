import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;
  await Deploy("OrangeEmitter");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
