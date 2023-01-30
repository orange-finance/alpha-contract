import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import {
  UniswapV3PoolAccessorMock,
  ERC20Mock,
  LiquidityAmountsMock,
} from "../../typechain-types/index";
import { MAX_UINT256 } from "../common";
import { getAddresses } from "../addresses";

const decimalWeth = 18;
const decimalUsdc = 6;

const wethAmount = BigNumber.from("2240").mul(
  BigNumber.from("10").pow(decimalWeth)
);
const usdcAmount = BigNumber.from("4320000").mul(
  BigNumber.from("10").pow(decimalUsdc)
);

async function dealAndSupplyUniswapPool(
  wethAddr: string,
  usdcAddr: string,
  poolAccessorAddr: string,
  liquidityAddr: string,
  to: string
) {
  let tx;
  const weth = (await ethers.getContractAt("ERC20Mock", wethAddr)) as ERC20Mock;
  const usdc = (await ethers.getContractAt("ERC20Mock", usdcAddr)) as ERC20Mock;
  const poolMock = (await ethers.getContractAt(
    "UniswapV3PoolAccessorMock",
    poolAccessorAddr
  )) as UniswapV3PoolAccessorMock;

  //mint
  tx = await weth.mint(to, wethAmount);
  tx.wait();
  console.log("weth.mint", tx);
  tx = await usdc.mint(to, usdcAmount);
  tx.wait();
  console.log("usdc.mint", tx);

  //approve
  tx = await weth.approve(poolAccessorAddr, MAX_UINT256);
  tx.wait();
  console.log("weth.approve", tx);
  tx = await usdc.approve(poolAccessorAddr, MAX_UINT256);
  tx.wait();
  console.log("usdc.approve", tx);

  // console liquditity
  // const liquidityMock = (await ethers.getContractAt(
  //   "LiquidityAmountsMock",
  //   liquidityAddr
  // )) as LiquidityAmountsMock;
  // const _liquidity = await liquidityMock.getLiquidityForAmounts(
  //   await liquidityMock.getSqrtRatioAtTick(BigNumber.from("-202339")),
  //   await liquidityMock.getSqrtRatioAtTick(BigNumber.from("-207240")),
  //   await liquidityMock.getSqrtRatioAtTick(BigNumber.from("-200820"))
  //   BigNumber.from("2240").mul(BigNumber.from("10").pow(decimalWeth)),
  //   BigNumber.from("4320000").mul(BigNumber.from("10").pow(decimalUsdc))
  // );
  // console.log(_liquidity, "_liquidity");

  tx = await poolMock.mint(
    BigNumber.from("-207240"),
    BigNumber.from("-200820"),
    wethAmount,
    usdcAmount
  );
  tx.wait();
  console.log("pool.add", tx);
}

async function main() {
  const a = getAddresses()!;
  await dealAndSupplyUniswapPool(
    a.Weth,
    a.Usdc,
    a.UniswapV3PoolAccessorMock,
    a.LiquidityAmountsMock,
    a.Deployer
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
