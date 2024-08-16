import hre from "hardhat";
import fs from "fs-extra";
import { Config } from "./config";

/**
 * @description Deploys library contracts.
 */
async function main() {
  const environ = Config.environ();
  const chain = await hre.ethers.provider.getNetwork().then((n) => n.chainId);
  const SafeAavePool = await hre.ethers.getContractFactory("SafeAavePool");

  const safeAavePool = await SafeAavePool.deploy().then((u) => u.deployed());

  // export as json file
  const savePath = Config.libSavePath(environ, chain);

  fs.ensureFileSync(savePath);

  fs.readFile(savePath, (err, data) => {
    if (err) throw err;

    const json = JSON.parse(data.toString() || "{}");

    json["SafeAavePool"] = {
      address: safeAavePool.address,
      args: [],
    };

    fs.writeJsonSync(savePath, json, { spaces: 2 });
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
