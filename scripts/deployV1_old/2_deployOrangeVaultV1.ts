import { ethers } from "hardhat";
import { Deploy, DeployLibraries } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta = {
  name: "OrangeVaultV1",
  symbol: "OrangeVaultV1",
};

async function main() {
  const a = getAddresses()!;
  await DeployLibraries(
    "OrangeVaultV1",
    { SafeAavePool: a.SafeAavePool },
    vaultMeta.name,
    vaultMeta.symbol,
    a.Weth,
    a.Usdc,
    a.UniswapPool,
    a.AavePool,
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
