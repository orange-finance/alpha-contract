import { ethers } from "hardhat";
import { Deploy, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

async function deployOrangeAlphaPeriphery(
  orangeAlphaVaultAddr: string
  orangeAlphaParametersAddr: string
) {
  await Deploy("OrangeAlphaPeriphery",orangeAlphaVaultAddr, orangeAlphaParametersAddr);
}

async function main() {
  const a = getAddresses()!;
  await deployOrangeAlphaPeriphery(a.OrangeAlphaVault, a.OrangeAlphaParameters);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
