import { ethers } from "hardhat";
import { Verify, ERC20metadata } from "../common";
import { getAddresses } from "../addresses";

const vaultMeta: ERC20metadata = {
  name: "OrangeDeltaVault",
  symbol: "OrangeDeltaVault",
  decimals: 6,
};

const verify = async () => {
  const a = getAddresses()!;

  await Verify(a.OrangeDeltaParameters, []);

  await Verify(a.OrangeDeltaVault, [
    vaultMeta.name,
    vaultMeta.symbol,
    a.UniswapPool,
    a.Weth,
    a.Usdc,
    a.UniswapRouter,
    a.AavePool,
    a.VDebtWeth,
    a.AUsdc,
    a.OrangeDeltaParameters,
  ]);

  await Verify(a.OrangeDeltaPeriphery, [
    a.OrangeDeltaVault,
    a.OrangeDeltaParameters,
  ]);

  await Verify(a.OrangeDeltaResolver, [
    a.OrangeDeltaVault,
    a.OrangeDeltaParameters,
  ]);

  await Verify(a.OrangeDeltaComputer, [
    a.OrangeDeltaVault,
    a.OrangeDeltaParameters,
  ]);
};

const main = async () => {
  await verify();
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
