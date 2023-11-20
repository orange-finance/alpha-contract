import hre from "hardhat";
import {
  impersonateAccount,
  setBalance,
} from "@nomicfoundation/hardhat-network-helpers";
import { z } from "zod";

namespace constants {
  export const chainId = 42161;
}

namespace schema {
  export const metadata = z.object({
    address: z.string(),
    args: z.array(z.string()),
  });

  export const contracts = z.object({
    SafeAavePool: metadata.optional(),
    OrangeVaultV1Initializable: metadata.optional(),
    OrangeStrategyImplV1: metadata.optional(),
    OrangeParametersV1: metadata.optional(),
    UniswapV3LiquidityPoolManagerDeployer: metadata.optional(),
    CamelotV3LiquidityPoolManagerDeployer: metadata.optional(),
    AaveLendingPoolManagerDeployer: metadata.optional(),
    OrangeVaultRegistry: metadata.optional(),
    OrangeVaultFactoryV1_0: metadata.optional(),
    OrangeEmitter: metadata.optional(),
    OrangeStoplossChecker: metadata.optional(),
  });

  export const externals = z.object({
    BalancerVault: z.string(),
    UniswapRouter: z.string(),
    AavePool: z.string(),
    Tokens: z.record(z.string()),
  });
}

type Contracts = z.infer<typeof schema.contracts>;

type Externals = z.infer<typeof schema.externals>;

export const config = {
  getMetadata: async (chain: number) => {
    const { default: metadata }: { default: Contracts } = await import(
      `./deployment/${chain}.json`
    );
    return metadata;
  },
  getExternals: async (chain: number) => {
    const { default: external }: { default: Externals } = await import(
      `./external/${chain}.json`
    );
    return external;
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
