import { ethers } from "hardhat";
import { getAddresses } from "../addresses";
import prompts from "prompts";

const questions: prompts.PromptObject[] = [
  {
    type: "text",
    name: "vault",
    message: "Enter the vault address to add",
  },
];

async function main() {
  const { OrangeStoplossChecker } = getAddresses() ?? {};

  if (!OrangeStoplossChecker)
    throw Error("no OrangeStoplossChecker address found");

  const { vault } = await prompts(questions);

  const v = await ethers.getContractAt("IOrangeVaultV1", vault);
  const params = await v.params();

  const p = await ethers.getContractAt("IOrangeParametersV1", params);

  const helper = await p.helper();

  if (helper === ethers.constants.AddressZero)
    throw Error("no helper found for the vault");

  const checker = await ethers.getContractAt(
    "OrangeStoplossChecker",
    OrangeStoplossChecker
  );

  const h = await ethers.getContractAt("OrangeStrategyHelperV1", helper);

  let tx = await h.setStrategist(checker.address, true);
  console.log("setting strategist for helper");
  console.log({ hash: tx.hash });
  await tx.wait();

  tx = await checker.addVault(vault, helper);
  console.log("adding vault to checker");
  console.log({ hash: tx.hash });

  await tx.wait();

  console.log("✨ vault successfully added");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
