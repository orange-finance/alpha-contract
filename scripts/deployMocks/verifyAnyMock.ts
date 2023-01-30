import { ethers } from "hardhat";
import { Verify } from "../common";

async function main() {
  await Verify("0x0c230a943c0f605b0545A6057332e3f447b0EBA4", []);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
