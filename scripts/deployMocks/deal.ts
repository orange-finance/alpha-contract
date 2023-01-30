import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { ERC20Mock } from "../../typechain-types/index";
import { getAddresses } from "../addresses";

const decimalWeth = 18;
const decimalUsdc = 6;

const wethAmount = BigNumber.from("10000").mul(
  BigNumber.from("10").pow(decimalWeth)
);
const usdcAmount = BigNumber.from("10000000").mul(
  BigNumber.from("10").pow(decimalUsdc)
);

async function deal(wethAddr: string, usdcAddr: string, to: string) {
  let tx;
  const weth = (await ethers.getContractAt("ERC20Mock", wethAddr)) as ERC20Mock;
  const usdc = (await ethers.getContractAt("ERC20Mock", usdcAddr)) as ERC20Mock;

  //mint
  tx = await weth.mint(to, wethAmount);
  tx.wait();
  console.log("weth.mint", tx);
  tx = await usdc.mint(to, usdcAmount);
  tx.wait();
  console.log("usdc.mint", tx);
}

async function main() {
  const a = getAddresses()!;
  await deal(a.Weth, a.Usdc, a.Deployer);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
