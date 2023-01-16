import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { AaveV3PoolMock, ERC20Mock } from "../../typechain-types/index";
import { MAX_UINT256, GetDecimals } from "../common";
import { getAddresses } from "../addresses";

const decimalWeth = 18;
const decimalUsdc = 6;

async function dealAndSupplyAave(
  wethAddr: string,
  usdcAddr: string,
  poolAddr: string,
  to: string
) {
  let tx;
  const weth = (await ethers.getContractAt("ERC20Mock", wethAddr)) as ERC20Mock;
  const usdc = (await ethers.getContractAt("ERC20Mock", usdcAddr)) as ERC20Mock;
  const pool = (await ethers.getContractAt(
    "AaveV3PoolMock",
    poolAddr
  )) as AaveV3PoolMock;

  // mint
  tx = await weth.mint(
    to,
    BigNumber.from("100000000").mul(BigNumber.from("10").pow(decimalWeth))
  );
  tx.wait();
  console.log("weth.mint", tx);
  tx = await usdc.mint(
    to,
    BigNumber.from("100000000").mul(BigNumber.from("10").pow(decimalUsdc))
  );
  tx.wait();
  console.log("usdc.mint", tx);
  //approve
  tx = await weth.approve(poolAddr, MAX_UINT256);
  tx.wait();
  console.log("weth.approve", tx);
  tx = await usdc.approve(poolAddr, MAX_UINT256);
  tx.wait();
  console.log("usdc.approve", tx);
  tx = await pool.supply(
    wethAddr,
    BigNumber.from("100000000").mul(BigNumber.from("10").pow(decimalWeth)),
    to,
    0,
    {
      gasLimit: 5_000_000,
    }
  );
  tx.wait();
  console.log("pool.supply.weth", tx);
  tx = await pool.supply(
    usdcAddr,
    BigNumber.from("100000000").mul(BigNumber.from("10").pow(decimalUsdc)),
    to,
    0,
    {
      gasLimit: 5_000_000,
    }
  );
  tx.wait();
  console.log("pool.supply.usdc", tx);
}

async function main() {
  const a = getAddresses()!;
  await dealAndSupplyAave(a.Weth, a.Usdc, a.AavePool, a.Deployer);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
