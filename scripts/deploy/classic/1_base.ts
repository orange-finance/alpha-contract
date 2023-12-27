import hre from "hardhat";
import fs from "fs-extra";
import { Config } from "./config";

/**
 * @description Deploys Base contracts. These are identical on a chain.
 */
async function main() {
  const environ = Config.environ();
  const chain = await hre.ethers.provider.getNetwork().then((n) => n.chainId);
  const meta = await Config.getLibMetadata(environ, chain);

  const UniV3ManagerDeployer = await hre.ethers.getContractFactory(
    "UniswapV3LiquidityPoolManagerDeployer"
  );
  const CamelotDeployer = await hre.ethers.getContractFactory(
    "CamelotV3LiquidityPoolManagerDeployer"
  );
  const AaveLendingPoolManagerDeployer = await hre.ethers.getContractFactory(
    "AaveLendingPoolManagerDeployer",
    {
      libraries: {
        SafeAavePool: meta.SafeAavePool.address,
      },
    }
  );

  const Registry = await hre.ethers.getContractFactory("OrangeVaultRegistry");
  const Factory = await hre.ethers.getContractFactory("OrangeVaultFactoryV1_0");
  const VaultImpl = await hre.ethers.getContractFactory(
    "OrangeVaultV1Initializable"
  );

  const StrategyImpl = await hre.ethers.getContractFactory(
    "OrangeStrategyImplV1Initializable"
  );

  const Emitter = await hre.ethers.getContractFactory("OrangeEmitter");
  const StoplossHub = await hre.ethers.getContractFactory(
    "OrangeStoplossChecker"
  );

  const vImpl = await VaultImpl.deploy().then((v) => v.deployed());
  const sImpl = await StrategyImpl.deploy().then((s) => s.deployed());
  const uniDeployer = await UniV3ManagerDeployer.deploy().then((u) =>
    u.deployed()
  );

  const camelotDeployer = await CamelotDeployer.deploy().then((u) =>
    u.deployed()
  );
  const aaveDeployer = await AaveLendingPoolManagerDeployer.deploy().then((u) =>
    u.deployed()
  );

  const em = await Emitter.deploy().then((e) => e.deployed());
  const sl = await StoplossHub.deploy().then((s) => s.deployed());

  const reg = await Registry.deploy().then((r) => r.deployed());
  const fac = await Factory.deploy(
    reg.address,
    vImpl.address,
    sImpl.address
  ).then((f) => f.deployed());

  // give deployer role to factory
  await reg.grantRole(await reg.VAULT_DEPLOYER_ROLE(), fac.address);

  // export as json file
  const outFile = Config.baseSavePath(environ, chain);
  fs.ensureFileSync(outFile);

  fs.readFile(outFile, (err, data) => {
    if (err) throw err;

    const json = JSON.parse(data.toString() || "{}");

    json["OrangeVaultV1Initializable"] = {
      address: vImpl.address,
      args: [],
    };

    json["OrangeStrategyImplV1Initializable"] = {
      address: sImpl.address,
      args: [],
    };

    json["UniswapV3LiquidityPoolManagerDeployer"] = {
      address: uniDeployer.address,
      args: [],
    };

    json["CamelotV3LiquidityPoolManagerDeployer"] = {
      address: camelotDeployer.address,
      args: [],
    };

    json["AaveLendingPoolManagerDeployer"] = {
      address: aaveDeployer.address,
      args: [],
    };

    json["OrangeVaultRegistry"] = {
      address: reg.address,
      args: [],
    };

    json["OrangeVaultFactoryV1_0"] = {
      address: fac.address,
      args: [reg.address, vImpl.address, sImpl.address],
    };

    json["OrangeEmitter"] = {
      address: em.address,
      args: [],
    };

    json["OrangeStoplossChecker"] = {
      address: sl.address,
      args: [],
    };

    fs.writeJsonSync(outFile, json, { spaces: 2 });
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
