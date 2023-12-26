import hre from "hardhat";
import { config } from "./config";

/**
 * This script verifies all Orange contracts deployed.
 */
async function main() {
  const chain = await hre.ethers.provider.getNetwork().then((n) => n.chainId);

  if (chain === 31337) {
    console.log("skipping verification on localhost");
    return;
  }

  const metadata = await config.getMetadata(chain);

  for (const [k, { address, args }] of Object.entries(metadata)) {
    if (!address || !args) {
      throw new Error(`missing address or args for ${k}`);
    }

    console.log(`verifying ${k} at ${address} with args ${args}`);

    try {
      await hre.run("verify:verify", {
        address,
        constructorArguments: args,
      });
    } catch (e) {
      if (
        e instanceof Error &&
        e.message.includes("Contract source code already verified")
      ) {
        console.log("already verified");
      } else {
        throw e;
      }
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
