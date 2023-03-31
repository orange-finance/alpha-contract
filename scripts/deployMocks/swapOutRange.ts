import { ethers } from "hardhat";
import { BigNumber, utils } from "ethers";
import {
  UniswapV3PoolAccessorMock,
  ERC20Mock,
} from "../../typechain-types/index";
import { MAX_UINT256 } from "../common";
import { getAddresses } from "../addresses";

const zeroForOne = false;
// const swapAmount = utils.parseEther("99990000");
const swapAmount = BigNumber.from("150000000000").mul(
  BigNumber.from("1000000")
);

async function swapOutRange(uniswapV3PoolAccessorMock: string) {
  let tx;
  const accessor = (await ethers.getContractAt(
    "UniswapV3PoolAccessorMock",
    uniswapV3PoolAccessorMock
  )) as UniswapV3PoolAccessorMock;

  let sqrtRatioX96 = await accessor.getSlippage(zeroForOne);
  console.log(sqrtRatioX96.toString(), "sqrtRatioX96");

  if (zeroForOne) {
    sqrtRatioX96 = sqrtRatioX96.mul(80).div(100);
  } else {
    sqrtRatioX96 = sqrtRatioX96.mul(120).div(100);
  }

  tx = await accessor.swap(zeroForOne, swapAmount, sqrtRatioX96);
  tx.wait();

  console.log("swap", tx);
}

async function main() {
  const a = getAddresses()!;
  await swapOutRange(a.UniswapV3PoolAccessorMock);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
