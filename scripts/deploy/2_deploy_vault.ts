import hre from "hardhat";
import fs from "fs-extra";
import path from "path";
import { OrangeVaultFactoryV1_0 } from "../../typechain-types";
import prompts from "prompts";
import kleur from "kleur";
import { config } from "./config";

/**
 * @description Deploys a Vault contract. You must have deployed the Base contracts first.
 */
async function main() {
  const chain = await hre.ethers.provider.getNetwork().then((n) => n.chainId);
  const signer = await config.getDefaultSigner();

  const md = await config.getMetadata(chain);
  const ext = await config.getExternals(chain);

  const multisig = config.getMultisigAccount(chain);

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
      type: "select",
      name: "version",
      message: "Select vault version",
      choices: [
        {
          title: "Delta Neutral Classic",
          value: "V1_DN_CLASSIC",
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
      initial: multisig,
    },
    {
      type: "text",
      name: "performanceFeeRecipient",
      message: "Enter performance fee recipient address",
      initial: multisig,
    },
    {
      type: "text",
      name: "liquidityPool",
      message: "Enter liquidity pool address",
    },
    {
      type: "select",
      name: "feeTier",
      message: "Select UniswapV3 Router fee tier (used for swap)",
      choices: [
        {
          title: "0.01% (best for very stable pairs)",
          value: 100,
        },
        {
          title: "0.05% (best for stable pairs)",
          value: 500,
        },
        {
          title: "0.30% (best for most pairs)",
          value: 3000,
        },
        {
          title: "1.00% (best for exotic pairs)",
          value: 10000,
        },
      ],
    },
  ];

  const q2: (
    tokens: { address: string; symbol: string }[]
  ) => prompts.PromptObject<string> = (tokens) => ({
    name: "token0",
    type: "select",
    message: "Select token0",
    choices: tokens.map((t) => ({
      title: t.symbol + " " + t.address.slice(0, 6) + "...",
      value: t.address,
    })),
  });

  const {
    version,
    poolType,
    depositCap,
    minDepositAmount,
    owner,
    performanceFeeRecipient,
    liquidityPool,
    feeTier,
  } = await prompts(q1, {
    onCancel: () => process.exit(0),
  });

  const liqM =
    poolType === "UniswapV3"
      ? md.UniswapV3LiquidityPoolManagerDeployer.address
      : md.CamelotV3LiquidityPoolManagerDeployer.address;

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
  const vSymbol0 = vToken0 === token0 ? symbol0 : symbol1;
  const vSymbol1 = vToken1 === token1 ? symbol1 : symbol0;

  const vSymbol = `o${vSymbol0}-${vSymbol1}`;

  const vc: OrangeVaultFactoryV1_0.VaultConfigStruct = {
    version,
    allowlistEnabled: false,
    balancer: ext.BalancerVault,
    depositCap,
    lendingPool: ext.AavePool,
    liquidityPool,
    minDepositAmount,
    name: vSymbol,
    owner,
    router: ext.UniswapRouter,
    routerFee: feeTier,
    symbol: vSymbol,
    token0: vToken0,
    token1: vToken1,
  };

  /**
   * @description
   * 1. owner address
   * 2. performance fee recipient
   * 3. performance fee divisor (fee / divisor) - 10 = 10% fee
   */
  const liqSetup = hre.ethers.utils.defaultAbiCoder.encode(
    ["address", "address", "uint128"],
    [owner, performanceFeeRecipient, 10]
  );

  const liqC: OrangeVaultFactoryV1_0.PoolManagerConfigStruct = {
    managerDeployer: liqM,
    setUpData: liqSetup,
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

  const strategist = config.getStrategist(chain);

  // confirm vault creation

  console.log(`🚨 Confirm vault creation:`);
  console.log("Version:", kleur.yellow(`${vc.version}`));
  console.log("Name:", kleur.yellow(`${vc.name}`));
  console.log("Symbol:", kleur.yellow(`${vc.symbol}`));
  console.log("Token0:", kleur.yellow(`${vc.token0}`));
  console.log("Token1:", kleur.yellow(`${vc.token1}`));
  console.log("Router fee tier:", kleur.yellow(`${vc.routerFee}`));
  console.log("Owner:", kleur.yellow(`${vc.owner}`));
  console.log("Strategist:", kleur.yellow(`${strategist}`));
  console.log("Allowlist enabled:", kleur.yellow(`${vc.allowlistEnabled}`));
  console.log("Deposit cap:", kleur.yellow(`${vc.depositCap}`));
  console.log("Min deposit amount:", kleur.yellow(`${vc.minDepositAmount}`));

  const { confirm } = await prompts({
    type: "confirm",
    name: "confirm",
    message: "Create vault?",
  });

  if (!confirm) process.exit(0);

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

  await helper.setStrategist(strategist, true).then((tx) => tx.wait());
  console.log("✨ EOA added as strategist");

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
