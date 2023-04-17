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

  //set merkle root
  const vault = (await ethers.getContractAt(
    "OrangeAlphaParameters",
    a.OrangeAlphaParameters
  )) as OrangeAlphaParameters;
  const tx = await vault.setMerkleRoot(root);
  console.log(tx);

  //console leaves
  const proof0 = await tree.getHexProof(leaves[0]);
  console.log(proof0);
  const proof1 = await tree.getHexProof(leaves[1]);
  console.log(proof1);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
