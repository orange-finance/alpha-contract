import hre from "hardhat";
import path from "path";
import {
  impersonateAccount,
  setBalance,
} from "@nomicfoundation/hardhat-network-helpers";
import { z } from "zod";

export const ENV = {
  PROD: "prod",
  QA: "qa",
  LOCAL: "local",
} as const;

export const Config = {
  environ: (): Config.Env => {
    const env = process.env.ENV;

    try {
      if (!env) throw new Error('environment variable "ENV" not set');
      if (!Object.values(ENV).includes(env as any))
        throw new Error(`ENV ${env} not supported`);
    } catch (e) {
      throw new Error(
        `error: ${e}\nsupported ENV values: ${Object.values(ENV).join(", ")}`
      );
    }

    return env as Config.Env;
  },

  deploymentDir: path.join(__dirname, "deployment"),

  libSavePath: (env: Config.Env, chain: number) => {
    return path.join(Config.deploymentDir, "lib", env, `${chain}.json`);
  },

  baseSavePath: (env: Config.Env, chain: number) => {
    return path.join(Config.deploymentDir, "base", env, `${chain}.json`);
  },

  vaultSavePath: (env: Config.Env, chain: number) => {
    return path.join(Config.deploymentDir, "vault", env, `${chain}.json`);
  },

  getLibMetadata: async (env: Config.Env, chain: number) => {
    const { default: metadata } = await import(Config.libSavePath(env, chain));

    return schema.lib.parse(metadata);
  },

  getBaseMetadata: async (env: Config.Env, chain: number) => {
    const { default: metadata } = await import(Config.baseSavePath(env, chain));

    return schema.base.parse(metadata);
  },

  getExternals: async (chain: number) => {
    const { default: external } = await import(`./external/${chain}.json`);
    return schema.externals.parse(external);
  },

  getDefaultSigner: async () => {
    const useFork =
      hre.network.name === "hardhat" &&
      hre.userConfig.networks?.hardhat?.forking?.enabled;

    const address = hre.ethers.utils.computeAddress(
      `0x${process.env.PRIVATE_KEY}`
    );

    if (useFork) {
      await setBalance(
        address,
        hre.ethers.BigNumber.from("100000000000000000000000")
      );
      await impersonateAccount(address);
    }

    return hre.ethers.getSigner(address);
  },

  getVaults: async (chain: number) => {
    const { default: vaults } = await import(
      `./deployment/vault/${chain}.json`
    );

    return z.record(schema.vault).parse(vaults);
  },

  /**
   * @note currently one strategist for all vaults
   */
  getStrategist: (_: number) => {
    return "0xd31583735e47206e9af728EF4f44f62B20db4b27";
  },
  getMultisigAccount: (chain: number) => {
    if (chain != 42161) throw new Error("the chain not supported");

    return "0x38E4157345Bd2c8Cf7Dbe4B0C75302c2038AB7Ec";
  },
};

namespace schema {
  const metadata = z.object({
    address: z.string(),
    args: z.array(z.string()),
  });

  export const lib = z.object({
    SafeAavePool: metadata,
  });

  export const base = z.object({
    OrangeVaultV1Initializable: metadata,
    OrangeStrategyImplV1Initializable: metadata,
    UniswapV3LiquidityPoolManagerDeployer: metadata,
    CamelotV3LiquidityPoolManagerDeployer: metadata,
    AaveLendingPoolManagerDeployer: metadata,
    StubLendingPoolManagerDeployer: metadata,
    OrangeVaultRegistry: metadata,
    OrangeVaultFactoryV1_0: metadata,
    OrangeEmitter: metadata,
    OrangeStoplossChecker: metadata,
  });

  export const externals = z.object({
    BalancerVault: z.string(),
    UniswapRouter: z.string(),
    AavePool: z.string(),
    Tokens: z.record(z.string()),
  });

  export const vault = z.object({
    token0: z.string(),
    token1: z.string(),
    poolType: z.string(),
    poolAddress: z.string(),
  });

  const errorMap: z.ZodErrorMap = (error, ctx) => {
    if (error.code === z.ZodIssueCode.invalid_type) {
      if (error.received === "undefined") {
        return {
          message: `${error.path.join(".")}: not defined in a json file`,
        };
      }
    }

    return { message: ctx.defaultError };
  };

  z.setErrorMap(errorMap);
}

export namespace Config {
  export type Env = typeof ENV[keyof typeof ENV];
}
