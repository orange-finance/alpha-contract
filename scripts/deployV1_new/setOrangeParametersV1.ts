import { ethers } from "hardhat";
import { Deploy } from "../common";
import { getAddresses } from "../addresses";
import { OrangeParametersV1 } from "../../typechain-types/contracts/coreV1";

async function main() {
  const a = getAddresses()!;

  const params = (await ethers.getContractAt(
    "OrangeParametersV1",
    a.OrangeParametersV1
  )) as OrangeParametersV1;

  const tx = await params.setAllowlistEnabled(false);
  console.log(tx);

  const tx2 = await params.setDepositCap(500_000_000_000);
  console.log(tx2);

  const tx3 = await params.setMinDepositAmount(10_000);
  console.log(tx3);

  const tx4 = await params.setHelper(a.OrangeStrategyHelperV1);
  console.log(tx4);

  const tx5 = await params.setStrategyImpl(a.OrangeStrategyImplV1);
  console.log(tx5);

  const tx6 = await params.transferOwnership(a.Owner);
  console.log(tx6);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
