import { ethers } from "hardhat";
import { BigNumber, utils } from "ethers";
import { UniswapV3PoolAccessorMock } from "../../typechain-types/index";
import { getAddresses } from "../addresses";

const isSwapReturn = true;
const swapTimes = 5;
const swapAmountZeroForOne = utils.parseEther("200");
const swapAmountOneForZero = BigNumber.from("1500000").mul(
  BigNumber.from("1000000")
);

async function swapInRange(uniswapV3PoolAccessorMock: string) {
  let tx;
  const accessor = (await ethers.getContractAt(
    "UniswapV3PoolAccessorMock",
    uniswapV3PoolAccessorMock
  )) as UniswapV3PoolAccessorMock;

  let sqrtRatioX96;
  for (let i = 0; i < swapTimes; i++) {
    //zero for one
    sqrtRatioX96 = await accessor.getSqrtRatioX96();
    sqrtRatioX96 = sqrtRatioX96.mul(80).div(100);

    tx = await accessor.swap(true, swapAmountZeroForOne, sqrtRatioX96);
    tx.wait();
    console.log("swap", tx);

    if (isSwapReturn) {
      //one for zero
      sqrtRatioX96 = await accessor.getSqrtRatioX96();
      sqrtRatioX96 = sqrtRatioX96.mul(120).div(100);

      tx = await accessor.swap(false, swapAmountOneForZero, sqrtRatioX96);
      tx.wait();
      console.log("swap", tx);
    }
  }
}

async function main() {
  const a = getAddresses()!;
  await swapInRange(a.UniswapV3PoolAccessorMock);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
