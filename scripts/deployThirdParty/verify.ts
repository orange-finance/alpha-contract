import { ethers } from "hardhat";
import { Verify, VerifyLibraries } from "../common";

const verify = async () => {
  await Verify("0x1A5f00303750a301f3Fd491C9915C65370b837C5", [
    "0x6d9d02c8CE73a239AC87Df96E7b881c1521F5531",
  ]);
};

const main = async () => {
  await verify();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
