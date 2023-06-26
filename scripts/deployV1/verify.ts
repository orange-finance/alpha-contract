import { ethers } from "hardhat";
import { Verify, VerifyLibraries } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta = {
  name: "OrangeVaultV1",
  symbol: "OrangeVaultV1",
};

const verify = async () => {
  const a = getAddresses()!;

  await Verify(a.OrangeParametersV1, []);

  await VerifyLibraries(a.OrangeVaultV1, { SafeAavePool: a.SafeAavePool }, [
    vaultMeta.name,
    vaultMeta.symbol,
    a.Weth,
    a.Usdc,
    a.UniswapPool,
    a.AavePool,
    a.OrangeAlphaParameters,
    a.UniswapRouter,
    500,
    a.Balancer,
  ]);

  await Verify(a.OrangeStrategyImplV1, []);

  await Verify(a.OrangeStrategyHelperV1, [a.OrangeVaultV1]);
};

const main = async () => {
  await verify();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
