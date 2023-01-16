import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { AaveV3PoolMock } from "../../typechain-types/contracts/mocks/AaveV3PoolMock";
import { Deploy, ERC20metadata } from "../common";

const wethTokenMeta: ERC20metadata = {
  name: "WETH",
  symbol: "WETH",
  decimals: 18,
};
const usdcTokenMeta: ERC20metadata = {
  name: "USDC",
  symbol: "USDC",
  decimals: 6,
};

async function deployWethAndUsdc() {
  // await Deploy(
  //   "ERC20Mock",
  //   wethTokenMeta.name,
  //   wethTokenMeta.symbol,
  //   wethTokenMeta.decimals
  // );
  await Deploy(
    "ERC20Mock",
    usdcTokenMeta.name,
    usdcTokenMeta.symbol,
    usdcTokenMeta.decimals
  );
}

async function main() {
  await deployWethAndUsdc();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
