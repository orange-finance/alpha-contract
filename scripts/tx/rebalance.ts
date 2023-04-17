import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeAlphaVault } from "../../typechain-types/index";

async function main() {
  const a = getAddresses()!;

  //set merkle root
  const vault = (await ethers.getContractAt(
    "OrangeAlphaVault",
    a.OrangeAlphaVault
  )) as OrangeAlphaVault;
  const tx = await vault.rebalance(-203520, -201020, -204520, -200020, 0, 0);
  console.log(tx);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
