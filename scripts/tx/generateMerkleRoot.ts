import { ethers } from "ethers";
import { getAddresses } from "../addresses";
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

const url =
  "https://raw.githubusercontent.com/orange-finance/whitelist/main/WL.json";

//get Json from Github
async function fetchGitHubJson(url: string): Promise<any> {
  const response = await fetch(url); //use node version ^18.0

  if (!response.ok) {
    throw new Error("Request Failed. Reason:" + response.status);
  }

  return await response.json();
}

async function hashed(target: any[]) {
  return target.map(({ address }) => {
    return ethers.utils.solidityKeccak256(["address"], [address]);
  });
}

async function main() {
  const a = getAddresses()!;
  const list = await fetchGitHubJson(url);
  console.log(list);

  const leaves = await hashed(list);
  const tree = await new MerkleTree(leaves, keccak256, { sort: true });
  const root = await tree.getHexRoot();

  console.log("root:", root);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
