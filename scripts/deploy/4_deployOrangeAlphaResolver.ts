import { ethers } from "hardhat";
import { Deploy, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

async function deployOrangeAlphaResolver(
  orangeAlphaVaultAddr: string
  orangeAlphaParametersAddr: string
) {
  await Deploy("OrangeAlphaResolver",orangeAlphaVaultAddr, orangeAlphaParametersAddr);
}

async function main() {
  const a = getAddresses()!;
  await deployOrangeAlphaResolver(a.OrangeAlphaVault, a.OrangeAlphaParameters);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
