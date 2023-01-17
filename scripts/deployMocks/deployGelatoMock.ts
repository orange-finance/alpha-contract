import { ethers } from "hardhat";
import { Deploy } from "../common";

async function main() {
  const lowerTick = -205680;
  const upperTick = -203760;
  const currentTick = -204760;
  await Deploy("GelatoMock", lowerTick, upperTick, currentTick);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
