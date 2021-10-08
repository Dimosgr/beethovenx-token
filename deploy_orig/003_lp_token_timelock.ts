import { HardhatRuntimeEnvironment } from "hardhat/types"

export default async function ({ getNamedAccounts, deployments }: HardhatRuntimeEnvironment) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()
  await deploy("MasterChefLpTokenTimelock", {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [
      "0x33276d43ada054a281d40a11d48310cdc0156fc2",
      "0xc4a114e1952Cfec7A953Bbe37b815Bb556579807",
      1633688102,
      "0x0e317Aa06F6C759a724ecD43548FB77bF5baC5b9",
      1,
    ],
  })
}
