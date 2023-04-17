import env, { ethers } from "hardhat";
import { BigNumber, Contract } from "ethers";
import { Libraries } from "hardhat/types";

export const NilAddress = "0x0000000000000000000000000000000000000000";
export const MAGIC_SCALE_1E8 = 1e8;
export const DAY = 60 * 60 * 24;
export const MAX_UINT256 = BigNumber.from("2")
  .pow(BigNumber.from("256"))
  .sub(BigNumber.from("1"));

export type ERC20metadata = {
  name: string;
  symbol: string;
  decimals: number;
};

export const Deploy = async (
  factoryName: string,
  ...args: any[]
): Promise<Contract> => {
  return await DeployLibraries(factoryName, undefined, ...args);
};

export const DeployLibraries = async (
  factoryName: string,
  libraries?: Libraries,
  ...args: any[]
): Promise<Contract> => {
  const contract: Contract = await (
    await ethers.getContractFactory(factoryName, { libraries: libraries })
  ).deploy(...args);
  await contract.deployed();
  console.log(factoryName + ': "' + contract.address + '",');
  return contract;
};

export const VerifyLibraries = async (
  address: string,
  libraries?: Libraries,
  args: any[]
) => {
  try {
    await env.run("verify:verify", {
      address: address,
      constructorArguments: args,
      libraries: libraries,
    });
  } catch (e: any) {
    if (e.message === "Missing or invalid ApiKey") {
      console.log("Skip verifing with", e.message);
      return;
    }
    if (e.message === "Contract source code already verified") {
      console.log("Skip verifing with", e.message);
      return;
    }
    throw e;
  }
};

export const Verify = async (address: string, args: any[]) => {
  await VerifyLibraries(address, undefined, args);
};
