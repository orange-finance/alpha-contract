import { ethers } from "hardhat";
import { Verify, VerifyLibraries } from "../common";

async function main() {
  await VerifyLibraries(
    "0x27c9C92CAcE4D5b5525DC1589805Fc2540f76B21",
    {
      GelatoOps: "0xadFf2D91Cc75C63e1A1bb882cFa9EB2b421a1B52",
    },
    []
  );

  await Verify("0x0F6E7a44e7994a1cFa68ba9116C313e7323a03E3", [
    "0x27c9C92CAcE4D5b5525DC1589805Fc2540f76B21",
  ]);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
