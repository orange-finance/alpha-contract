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

  // await Verify(a.CamelotV3LiquidityPoolManagerUsdceWeth, [
  //   a.Usdc,
  //   a.Weth,
  //   a.CamelotWethUsdcePoolAddr,
  // ]);

  // await Verify(a.AaveLendingPoolManagerCamelotUsdceWeth, [
  //   a.Usdc,
  //   a.Weth,
  //   a.AavePool,
  // ]);

  await Verify(a.OrangeVaultV1CamelotUsdceWeth, [
    vaultMeta.name,
    vaultMeta.symbol,
    a.Usdc,
    a.Weth,
    a.CamelotV3LiquidityPoolManagerUsdceWeth,
    a.AaveLendingPoolManagerCamelotUsdceWeth,
    a.OrangeParametersV1CamelotUsdceWeth,
    a.UniswapRouter,
    500,
    a.Balancer,
  ]);

  // await Verify(a.OrangeStrategyImplV1, []);

  await Verify(a.OrangeStrategyHelperV1CamelotUsdceWeth, [
    a.OrangeVaultV1CamelotUsdceWeth,
  ]);
};

const main = async () => {
  await verify();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
