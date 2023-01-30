import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { getAddresses } from "../addresses";
import { IUniswapV3Factory, IUniswapV3Pool } from "../../typechain-types/index";

const sqrtPriceX96 = BigNumber.from("2843236571771623993513305");

async function createUniswapPool(
  wethAddr: string,
  usdcAddr: string,
  uniswapFactory: string
) {
  let tx;
  let receipt;
  const factroy = (await ethers.getContractAt(
    "IUniswapV3Factory",
    uniswapFactory
  )) as IUniswapV3Factory;

  tx = await factroy.createPool(usdcAddr, wethAddr, 3000);
  receipt = await tx.wait();
  console.log('Token0: "' + receipt.events![0].args![0] + '",');
  console.log('Token1: "' + receipt.events![0].args![1] + '",');
  console.log('Fee: "' + receipt.events![0].args![2] + '",');
  console.log('TickSpacing: "' + receipt.events![0].args![3] + '",');
  console.log('Pool: "' + receipt.events![0].args![4] + '",');

  //initialize
  const poolAddr = receipt.events![0].args![4];
  const pool = (await ethers.getContractAt(
    "IUniswapV3Pool",
    poolAddr
  )) as IUniswapV3Pool;
  pool.initialize(sqrtPriceX96);
}

async function main() {
  const a = getAddresses()!;
  await createUniswapPool(a.Weth, a.Usdc, a.UniswapFactory);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
