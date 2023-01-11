import { ethers } from "hardhat";
import { Verify, NilAddress, ERC20metadata } from "../common";
// import {} from "../addresses";

const meta: ERC20metadata = {
  name: "OrangeAlphaVault",
  symbol: "DVV1",
  decimals: 6,
};

const verify = async () => {
  await Verify("", [
    meta.name,
    meta.symbol,
    NilAddress,
    NilAddress,
    -205760,
    -203760,
    NilAddress,
  ]);
};

const main = async () => {
  await verify();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
