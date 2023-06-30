import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;

  await Deploy(
    "CamelotV3LiquidityPoolManager",
    a.Usdc,
    a.Weth,
    a.CamelotWethUsdcePoolAddr
  );

  await DeployLibraries(
    "AaveLendingPoolManager",
    { SafeAavePool: a.SafeAavePool },
    a.Usdc,
    a.Weth,
    a.AavePool
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
