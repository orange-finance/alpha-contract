import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

async function main() {
  const a = getAddresses()!;

  await Deploy(
    "UniswapV3LiquidityPoolManager",
    a.Usdc,
    a.Arb,
    a.UniswapPoolArb
  );

  await DeployLibraries(
    "AaveLendingPoolManager",
    { SafeAavePool: a.SafeAavePool },
    a.Usdc,
    a.Arb,
    a.AavePool
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
