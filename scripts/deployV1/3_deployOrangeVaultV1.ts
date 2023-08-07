import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta = {
  name: "OrangeVaultV1",
  symbol: "OrangeVaultV1",
};

async function main() {
  const a = getAddresses()!;
  await Deploy(
    "OrangeVaultV1",
    vaultMeta.name,
    vaultMeta.symbol,
    a.Usdc,
    a.Arb,
    a.CamelotV3LiquidityPoolManager,
    a.AaveLendingPoolManager,
    a.OrangeParametersV1,
    a.UniswapRouter,
    500,
    a.Balancer
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
