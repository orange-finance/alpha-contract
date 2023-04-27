import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeAlphaParameters } from "../../typechain-types/index";
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

async function hashed(target: any[]) {
  return target.map(({ address }) => {
    return ethers.utils.solidityKeccak256(["address"], [address]);
  });
}

const list = [
  {
    address: "",
  },
  {
    address: "",
  },
  {
    address: "",
  },
  {
    address: "",
  },
  {
    address: "",
  },
  {
    address: "",
  },
  {
    address: "",
  },
];

async function main() {
  const a = getAddresses()!;

  const leaves = await hashed(list);
  const tree = await new MerkleTree(leaves, keccak256, { sort: true });
  const root = await tree.getHexRoot();

  console.log("root:", root);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
