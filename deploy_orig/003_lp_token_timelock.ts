import { HardhatRuntimeEnvironment } from "hardhat/types"

export default async function ({ getNamedAccounts, deployments }: HardhatRuntimeEnvironment) {
  const { deploy } = deployments
  const { deployer } = await getNamedAccounts()

  /*

        IERC20 token_,
        address beneficiary_,
        uint256 releaseTime_,
        BeethovenxMasterChef masterChef_,
        uint256 masterChefPoolId_
   */
  await deploy("MasterChefLpTokenTimelock", {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [
      "0x03c6B3f09D2504606936b1A4DeCeFaD204687890",
      "0x0EDfcc1b8D082Cd46d13Db694b849D7d8151C6D5",
      1650622502000,
      "0x8166994d9ebBe5829EC86Bd81258149B87faCfd3",
      0,
    ],
  })
}
