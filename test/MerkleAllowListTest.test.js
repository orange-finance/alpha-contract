const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

async function hashed(target) {
  return target.map(({ address }) => {
    return ethers.utils.solidityKeccak256(["address"], [address]);
  });
}

describe("MerkleAllowListTest", function () {
  before(async () => {
    //import
    [alice, bob, carol] = await ethers.getSigners();
    const MerkleAllowListMock = await ethers.getContractFactory(
      "MerkleAllowListMock"
    );

    // console.log(bob.address);
    // console.log(bob.address.toLowerCase());
    let list = [
      {
        address: alice.address,
      },
      {
        address: "0x70997970c51812dc3a010c7d01b50e0d17dc79c8", //bob.address (lowerCase)
      },
      {
        address: carol.address.toLowerCase(), //lowerCase
      },
    ];
    const leaves = await hashed(list);
    const tree = await new MerkleTree(leaves, keccak256, { sort: true });
    const root = await tree.getHexRoot();

    mock = await MerkleAllowListMock.deploy();
    mock.setMerkleRoot(root);

    const leaf0 = leaves[0];
    proof0 = await tree.getHexProof(leaf0);
    const leaf1 = leaves[1];
    proof1 = await tree.getHexProof(leaf1);
    const leaf2 = leaves[2];
    proof2 = await tree.getHexProof(leaf2);
  });

  describe("exec", function () {
    it("success", async () => {
      await mock.connect(alice).exec(proof0);
      await mock.connect(bob).exec(proof1);
      await mock.connect(carol).exec(proof2);
    });
    it("fail", async () => {
      await expect(mock.connect(alice).exec(proof1)).to.revertedWith(
        "MerkleAllowList: Caller is not on allowlist."
      );
    });
    it("fail2", async () => {
      await expect(mock.connect(carol).exec(proof0)).to.revertedWith(
        "MerkleAllowList: Caller is not on allowlist."
      );
    });
  });
});
