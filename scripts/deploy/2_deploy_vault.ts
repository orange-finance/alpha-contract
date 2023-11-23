import hre from "hardhat";
import fs from "fs-extra";
import path from "path";
import { OrangeVaultFactoryV1_0 } from "../../typechain-types";
import prompts from "prompts";
import { config } from "./config";

/**
 * @description Deploys a Vault contract. You must have deployed the Base contracts first.
 */
async function main() {
  const chain = await hre.ethers.provider.getNetwork().then((n) => n.chainId);
  const signer = await config.getDefaultSigner();

  const md = await config.getMetadata(chain);
  const ext = await config.getExternals(chain);

  const q1: prompts.PromptObject<string>[] = [
    {
      type: "select",
      name: "poolType",
      message: "Select liquidity pool type",
      choices: [
        {
          title: "UniswapV3",
          value: "UniswapV3",
        },
        {
          title: "CamelotV3",
          value: "CamelotV3",
        },
      ],
    },
    {
      type: "text",
      name: "depositCap",
      message: "Enter deposit cap",
    },
    {
      type: "text",
      name: "minDepositAmount",
      message: "Enter min deposit amount",
      initial: 10000,
    },
    {
      type: "text",
      name: "owner",
      message: "Enter owner address",
      initial: signer.address,
    },
    {
      type: "text",
      name: "liquidityPool",
      message: "Enter liquidity pool address",
    },
  ];

  const q2: (
    tokens: { address: string; symbol: string }[]
  ) => prompts.PromptObject<string> = (tokens) => ({
    name: "token0",
    type: "select",
    message: "Select token0",
    choices: tokens.map((t) => ({
      title: t.symbol,
      value: t.address,
    })),
  });

  const { poolType, depositCap, minDepositAmount, owner, liquidityPool } =
    await prompts(q1, {
      onCancel: () => process.exit(0),
    });

  const liqM =
    poolType === "UniswapV3"
      ? md.UniswapV3LiquidityPoolManagerDeployer.address
      : md.CamelotV3LiquidityPoolManagerDeployer.address;

  // TODO: redeploy factory to apply latest changes (dynamic version support, fee event emission)
  // TODO: redeploy registry when production ready
  const factory = await hre.ethers.getContractAt(
    "OrangeVaultFactoryV1_0",
    md.OrangeVaultFactoryV1_0.address,
    signer
  );

  const pool = await hre.ethers.getContractAt(
    "IAlgebraPoolImmutables",
    liquidityPool,
    signer
  );
  const token0 = await pool.token0();
  const token1 = await pool.token1();

  const erc20 = await hre.artifacts.readArtifact(
    "@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"
  );

  const symbol0 = await hre.ethers
    .getContractAtFromArtifact(erc20, token0, signer)
    .then((c) => c.symbol());

  const symbol1 = await hre.ethers
    .getContractAtFromArtifact(erc20, token1, signer)
    .then((c) => c.symbol());

  const { token0: vToken0 } = await prompts(
    q2([
      { address: token0, symbol: symbol0 },
      { address: token1, symbol: symbol1 },
    ])
  );

  const vToken1 = vToken0 === token0 ? token1 : token0;

  console.log({ vToken0, vToken1 });

  const vc: OrangeVaultFactoryV1_0.VaultConfigStruct = {
    version: "V1_DN_CLASSIC",
    allowlistEnabled: true,
    balancer: ext.BalancerVault,
    depositCap,
    lendingPool: ext.AavePool,
    liquidityPool,
    minDepositAmount,
    name: "Orange Vault",
    owner,
    router: ext.UniswapRouter,
    routerFee: 0,
    symbol: "ORANGE",
    token0: vToken0,
    token1: vToken1,
  };

  const liqC: OrangeVaultFactoryV1_0.PoolManagerConfigStruct = {
    managerDeployer: liqM,
    setUpData: hre.ethers.constants.HashZero,
  };

  const lenC: OrangeVaultFactoryV1_0.PoolManagerConfigStruct = {
    managerDeployer: md.AaveLendingPoolManagerDeployer.address,
    setUpData: hre.ethers.constants.HashZero,
  };

  const sc: OrangeVaultFactoryV1_0.StrategyConfigStruct = {
    strategist: signer.address,
  };

  const v = await factory.callStatic.createVault(vc, liqC, lenC, sc, {
    from: signer.address,
  });

  const beforeBal = await hre.ethers.provider.getBalance(signer.address);

  await factory.createVault(vc, liqC, lenC, sc).then((tx) => tx.wait());
  console.log("✨ Vault created: ", v);

  const vault = await hre.ethers.getContractAt("IOrangeVaultV1", v, signer);

  const params = await hre.ethers.getContractAt(
    "OrangeParametersV1",
    await vault.params(),
    signer
  );

  const emitter = await hre.ethers.getContractAt(
    "OrangeEmitter",
    md.OrangeEmitter.address,
    signer
  );

  const checker = await hre.ethers.getContractAt(
    "OrangeStoplossChecker",
    md.OrangeStoplossChecker.address,
    signer
  );

  const helper = await hre.ethers.getContractAt(
    "OrangeStrategyHelperV1",
    await params.helper(),
    signer
  );

  // set vault to emitter
  await emitter.pushVaultV1(v).then((tx) => tx.wait());
  console.log("✨ Vault added to emitter");

  // set stoploss checker as strategist

  await helper.setStrategist(checker.address, true).then((tx) => tx.wait());
  console.log("✨ Stoploss checker added as strategist");

  // add vault to checker
  await checker.addVault(v, helper.address).then((tx) => tx.wait());
  console.log("✨ Vault added to checker");

  // gas used
  const afterBal = await hre.ethers.provider.getBalance(signer.address);
  const gasUsed = Math.abs(afterBal.sub(beforeBal).toNumber());
  console.log("⛽️ Gas used: ", gasUsed);

  // export as json file
  const outFile = path.join(__dirname, "deployment", "vault", `${chain}.json`);
  fs.ensureFileSync(outFile);

  fs.readFile(outFile, (err, data) => {
    if (err) throw err;

    const json = JSON.parse(data.toString() || "{}");

    json[v] = {
      token0,
      token1,
      poolType,
      poolAddress: liquidityPool,
    };

    fs.writeJsonSync(outFile, json, { spaces: 2 });

    console.log(`✨ Vault data saved to ${outFile}`);
  });
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
