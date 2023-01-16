import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import {
  IUniswapV3Pool,
  ERC20Mock,
  LiquidityAmountsMock,
} from "../../typechain-types/index";
import { MAX_UINT256 } from "../common";
import { getAddresses } from "../addresses";

const decimalWeth = 18;
const decimalUsdc = 6;

async function dealAndSupplyAave(
  wethAddr: string,
  usdcAddr: string,
  poolAddr: string,
  liquidityAddr: string,
  to: string
) {
  let tx;
  const weth = (await ethers.getContractAt("ERC20Mock", wethAddr)) as ERC20Mock;
  const usdc = (await ethers.getContractAt("ERC20Mock", usdcAddr)) as ERC20Mock;
  const pool = (await ethers.getContractAt(
    "IUniswapV3Pool",
    poolAddr
  )) as IUniswapV3Pool;
  const liquidity = (await ethers.getContractAt(
    "LiquidityAmountsMock",
    liquidityAddr
  )) as LiquidityAmountsMock;

  // mint
  // tx = await weth.mint(
  //   to,
  //   BigNumber.from("100000000").mul(BigNumber.from("10").pow(decimalWeth))
  // );
  // tx.wait();
  // console.log("weth.mint", tx);
  // tx = await usdc.mint(
  //   to,
  //   BigNumber.from("133300000000").mul(BigNumber.from("10").pow(decimalUsdc))
  // );
  // tx.wait();
  // console.log("usdc.mint", tx);
  // //approve
  // tx = await weth.approve(poolAddr, MAX_UINT256);
  // tx.wait();
  // console.log("weth.approve", tx);
  // tx = await usdc.approve(poolAddr, MAX_UINT256);
  // tx.wait();
  // console.log("usdc.approve", tx);

  const wethAmount = BigNumber.from("100000000").mul(
    BigNumber.from("10").pow(decimalWeth)
  );
  console.log(wethAmount, "wethAmount");
  const usdcAmount = BigNumber.from("133300000000").mul(
    BigNumber.from("10").pow(decimalUsdc)
  );
  console.log(usdcAmount, "usdcAmount");
  const _liquidity = await liquidity.getLiquidityForAmounts(
    BigNumber.from("134896327180229621995865"),
    BigNumber.from("59886222956408988699225381"),
    BigNumber.from("2841558812035677332848032"),
    BigNumber.from("100000000").mul(BigNumber.from("10").pow(decimalWeth)),
    BigNumber.from("133300000000").mul(BigNumber.from("10").pow(decimalUsdc))
  );
  console.log(_liquidity, "_liquidity");

  tx = await pool.mint(
    to,
    BigNumber.from("-265680"),
    BigNumber.from("-143760"),
    BigNumber.from("3765207895325146981750"),
    ""
  );
  tx.wait();
  console.log("pool.add", tx);
}

async function main() {
  const a = getAddresses()!;
  await dealAndSupplyAave(
    a.Weth,
    a.Usdc,
    a.UniswapPool,
    a.LiquidityAmountsMock,
    a.Deployer
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
