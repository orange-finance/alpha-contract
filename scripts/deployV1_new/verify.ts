import { ethers } from "hardhat";
import { Verify, VerifyLibraries } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta = {
  name: "OrangeVaultV1",
  symbol: "OrangeVaultV1",
};

const verify = async () => {
  const a = getAddresses()!;

  // await Verify(a.OrangeParametersV1CamelotUsdceWeth, []);

  await Verify(a.UniswapV3LiquidityPoolManager, [
    a.Usdc,
    a.Weth,
    a.UniswapPool,
  ]);

  // await Verify(a.AaveLendingPoolManager, [
  //   a.Usdc,
  //   a.Weth,
  //   a.AavePool,
  // ]);

  // await Verify(a.OrangeVaultV1, [
  //   vaultMeta.name,
  //   vaultMeta.symbol,
  //   a.Usdc,
  //   a.Weth,
  //   a.UniswapV3LiquidityPoolManager,
  //   a.AaveLendingPoolManager,
  //   a.OrangeParametersV1,
  //   a.UniswapRouter,
  //   500,
  //   a.Balancer,
  // ]);

  // await Verify(a.OrangeStrategyImplV1, []);

  // await Verify(a.OrangeStrategyHelperV1, [a.OrangeStrategyHelperV1]);
};

const main = async () => {
  await verify();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
