import hre from "hardhat";
import fs from "fs-extra";
import path from "path";
import { OrangeVaultFactoryV1_0, ERC20 } from "../../../typechain-types";
import prompts from "prompts";
import { config } from "./config";

const input: (
  chain: number
) => Promise<prompts.PromptObject<string>[]> = async (chain) => {
  const signer = await config.getDefaultSigner();

  const ext = await config.getExternals(chain);
  const tokens = ext.Tokens;

  return [
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
      type: "select",
      name: "token0",
      message: "Select token0",
      choices: Object.entries(tokens).map(([k, v]) => ({
        title: k,
        value: v,
      })),
    },
    {
      type: "select",
      name: "token1",
      message: "Select token1",
      choices: Object.entries(tokens).map(([k, v]) => ({
        title: k,
        value: v,
      })),
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
};
async function main() {
  const chain = await hre.ethers.provider.getNetwork().then((n) => n.chainId);
  const signer = await config.getDefaultSigner();

  const md = await config.getMetadata(chain);

  const ext = await config.getExternals(chain);
  const balancer = ext.BalancerVault;
  const uni = ext.UniswapRouter;
  const aave = ext.AavePool;

  if (!balancer) throw new Error("Balancer address not set");
  if (!uni) throw new Error("Uniswap address not set");
  if (!aave) throw new Error("Aave address not set");

  if (!md.OrangeVaultFactoryV1_0) {
    throw new Error("Factory not deployed");
  }

  if (!md.OrangeEmitter) {
    throw new Error("Emitter not deployed");
  }

  if (!md.UniswapV3LiquidityPoolManagerDeployer) {
    throw new Error("UniswapV3LiquidityPoolManagerDeployer not deployed");
  }

  if (!md.CamelotV3LiquidityPoolManagerDeployer) {
    throw new Error("CamelotV3LiquidityPoolManagerDeployer not deployed");
  }

  if (!md.AaveLendingPoolManagerDeployer) {
    throw new Error("AaveLendingPoolManagerDeployer not deployed");
  }

  if (!md.OrangeStoplossChecker) {
    throw new Error("OrangeStoplossChecker not deployed");
  }

  const _in = await input(chain);
  const {
    poolType,
    token0,
    token1,
    depositCap,
    minDepositAmount,
    owner,
    liquidityPool,
  } = await prompts(_in);

  const liqM =
    poolType === "UniswapV3"
      ? md.UniswapV3LiquidityPoolManagerDeployer.address
      : md.CamelotV3LiquidityPoolManagerDeployer.address;

  const factory = await hre.ethers.getContractAt(
    "OrangeVaultFactoryV1_0",
    md.OrangeVaultFactoryV1_0.address,
    signer
  );

  const vc: OrangeVaultFactoryV1_0.VaultConfigStruct = {
    allowlistEnabled: true,
    balancer,
    depositCap,
    lendingPool: aave,
    liquidityPool,
    minDepositAmount,
    name: "Orange Vault",
    owner,
    router: uni,
    routerFee: 0,
    symbol: "ORANGE",
    token0,
    token1,
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
