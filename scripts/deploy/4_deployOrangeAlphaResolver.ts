import { ethers } from "hardhat";
import { Deploy, DeployLibraries, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

async function deployOrangeAlphaResolver(
  orangeAlphaVaultAddr: string,
  orangeAlphaParametersAddr: string
) {
  const uniswapV3Twap = await Deploy("UniswapV3Twap");

  await DeployLibraries(
    "OrangeAlphaResolver",
    { UniswapV3Twap: uniswapV3Twap.address },
    orangeAlphaVaultAddr,
    orangeAlphaParametersAddr
  );
}

async function main() {
  const a = getAddresses()!;
  await deployOrangeAlphaResolver(a.OrangeAlphaVault, a.OrangeAlphaParameters);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
