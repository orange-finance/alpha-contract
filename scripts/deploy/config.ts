import hre from "hardhat";
import {
  impersonateAccount,
  setBalance,
} from "@nomicfoundation/hardhat-network-helpers";
import { z } from "zod";

export const config = {
  getMetadata: async (chain: number) => {
    const { default: metadata } = await import(`./deployment/${chain}.json`);

    return schema.contracts.parse(metadata);
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
};

namespace schema {
  const metadata = z.object({
    address: z.string(),
    args: z.array(z.string()),
  });

  export const contracts = z.object({
    SafeAavePool: metadata,
    OrangeVaultV1Initializable: metadata,
    OrangeStrategyImplV1: metadata,
    UniswapV3LiquidityPoolManagerDeployer: metadata,
    CamelotV3LiquidityPoolManagerDeployer: metadata,
    AaveLendingPoolManagerDeployer: metadata,
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
