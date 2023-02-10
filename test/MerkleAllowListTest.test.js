const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");

async function hashed(target) {
  return target.map(({ index, address }) => {
    return ethers.utils.solidityKeccak256(
      ["uint256", "address"],
      [index, address]
    );
  });
}

describe("MerkleAllowListTest", function () {
  before(async () => {
    //import
    [alice, bob, carol] = await ethers.getSigners();
    const MerkleAllowListMock = await ethers.getContractFactory(
      "MerkleAllowListMock"
    );

    let list = [
      {
        index: 0,
        address: alice.address,
      },
      {
        index: 1,
        address: bob.address,
      },
    ];
    const leaves = await hashed(list);
    const tree = await new MerkleTree(leaves, keccak256, { sort: true });
    const root = await tree.getHexRoot();

    mock = await MerkleAllowListMock.deploy(root);

    const leaf0 = leaves[0];
    proof0 = await tree.getHexProof(leaf0);
    const leaf1 = leaves[1];
    proof1 = await tree.getHexProof(leaf1);
  });

  describe("exec", function () {
    it("success", async () => {
      await mock.connect(alice).exec(0, proof0);
      await mock.connect(bob).exec(1, proof1);
    });
    it("fail", async () => {
      await expect(mock.connect(alice).exec(0, proof1)).to.revertedWith(
        "MerkleAllowList: Caller is not on allowlist."
      );
    });
    it("fail2", async () => {
      await expect(mock.connect(carol).exec(0, proof0)).to.revertedWith(
        "MerkleAllowList: Caller is not on allowlist."
      );
    });
  });
});
