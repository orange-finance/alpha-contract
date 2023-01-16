import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { AaveV3PoolMock, ERC20Mock } from "../../typechain-types/index";
import { MAX_UINT256 } from "../common";
import { getAddresses } from "../addresses";

async function approveAll(wethAddr: string, usdcAddr: string, to: string) {
  let tx;
  const weth = (await ethers.getContractAt("ERC20Mock", wethAddr)) as ERC20Mock;
  const usdc = (await ethers.getContractAt("ERC20Mock", usdcAddr)) as ERC20Mock;

  //approve
  tx = await weth.approve(to, MAX_UINT256);
  tx.wait();
  console.log("weth.approve", tx);
  tx = await usdc.approve(to, MAX_UINT256);
  tx.wait();
  console.log("usdc.approve", tx);
}

async function main() {
  const a = getAddresses()!;
  await approveAll(a.Weth, a.Usdc, a.OrangeAlphaVault);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
