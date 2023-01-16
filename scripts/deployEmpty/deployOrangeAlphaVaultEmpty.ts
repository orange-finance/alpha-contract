import env, { ethers } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { Deploy, DeployLibraries, NilAddress, ERC20metadata } from "../common";
// import {} from "../addresses";

const meta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "ORANGE_ALPHA_VAULT",
  decimals: 6,
};

async function deploy() {
  const OrangeAlphaVaultEmpty = await Deploy(
    "OrangeAlphaVaultEmpty",
    meta.name,
    meta.symbol,
    NilAddress,
    NilAddress,
    -205760,
    -203760
  );
}

async function main() {
  await deploy();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
