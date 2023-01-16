import { ethers } from "hardhat";
import { getAddresses } from "../addresses";
import { Deploy } from "../common";

async function deployUniswapPoolAccessor(pool: string) {
  await Deploy("UniswapV3PoolAccessorMock", pool);
}

async function main() {
  const a = getAddresses()!;
  await deployUniswapPoolAccessor(a.UniswapPool);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
