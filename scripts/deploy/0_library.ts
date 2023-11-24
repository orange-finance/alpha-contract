import hre from "hardhat";
import fs from "fs-extra";
import path from "path";

/**
 * @description Deploys library contracts.
 */
async function main() {
  const chain = await hre.ethers.provider.getNetwork().then((n) => n.chainId);
  const SafeAavePool = await hre.ethers.getContractFactory("SafeAavePool");
  const PerformanceFee = await hre.ethers.getContractFactory("PerformanceFee");

  const safeAavePool = await SafeAavePool.deploy().then((u) => u.deployed());
  const performanceFee = await PerformanceFee.deploy().then((u) =>
    u.deployed()
  );

  // export as json file
  const outFile = path.join(__dirname, "deployment", `${chain}.json`);

  fs.ensureFileSync(outFile);

  fs.readFile(outFile, (err, data) => {
    if (err) throw err;

    const json = JSON.parse(data.toString());

    json["SafeAavePool"] = {
      address: safeAavePool.address,
      args: [],
    };

    json["PerformanceFee"] = {
      address: performanceFee.address,
      args: [],
    };

    fs.writeJsonSync(outFile, json, { spaces: 2 });
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
