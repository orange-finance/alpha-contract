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
    a.Weth,
    a.CamelotV3LiquidityPoolManagerUsdceWeth,
    a.AaveLendingPoolManagerCamelotUsdceWeth,
    a.OrangeParametersV1CamelotUsdceWeth,
    a.UniswapRouter,
    500,
    a.Balancer
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
