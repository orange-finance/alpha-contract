import { ethers } from "hardhat";
import { Verify, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

const wethMeta: ERC20metadata = {
  name: "WETH",
  symbol: "WETH",
  decimals: 18,
};
const usdcMeta: ERC20metadata = {
  name: "USDC",
  symbol: "USDC",
  decimals: 6,
};

const verifyMock = async () => {
  const a = getAddresses()!;
  // await Verify(a.Weth, [wethMeta.name, wethMeta.symbol, wethMeta.decimals]);
  // await Verify(a.Usdc, [usdcMeta.name, usdcMeta.symbol, usdcMeta.decimals]);
  // await Verify(a.AavePool, []);
  // await Verify(a.VDebtWeth, [
  //   a.VDebtWeth,
  //   a.AavePool,
  //   wethMeta.decimals,
  //   "vDebt" + wethMeta.name,
  //   "vDebt" + wethMeta.name,
  // ]);
  // await Verify(a.AUsdc, [
  //   a.Usdc,
  //   a.AavePool,
  //   usdcMeta.decimals,
  //   "a" + usdcMeta.name,
  //   "a" + usdcMeta.name,
  // ]);
  // await Verify(a.UniswapPool, []);
  // await Verify(a.UniswapV3PoolAccessorMock, [a.UniswapPool]);
  await Verify(a.LiquidityAmountsMock, []);
};

const main = async () => {
  await verifyMock();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
