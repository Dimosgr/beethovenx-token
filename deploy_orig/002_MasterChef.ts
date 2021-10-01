import { bn } from "../test/utilities"
import { HardhatRuntimeEnvironment } from "hardhat/types"
import { BeethovenxMasterChef, BeethovenxToken, Timelock } from "../types"

export default async function ({ ethers, deployments, getNamedAccounts, network }: HardhatRuntimeEnvironment) {
  const { deploy } = deployments
  const { deployer, dev, treasury } = await getNamedAccounts()
  const beetsDeployment = await deployments.get("BeethovenxToken")
  const beets: BeethovenxToken = (await ethers.getContractAt("BeethovenxToken", beetsDeployment.address)) as BeethovenxToken

  const timelockDeployment = await deployments.get("Timelock")
  const timelock: Timelock = (await ethers.getContractAt("Timelock", timelockDeployment.address)) as Timelock

  const beetxPerBlock = bn(505, 16)

  const startBlock = process.env.DEPLOYMENT_MC_START_BLOCK

  const { address } = await deploy("BeethovenxMasterChef", {
    from: deployer,
    args: [beets.address, process.env.TREASURY_ADDRESS, beetxPerBlock, startBlock],
    log: true,
    deterministicDeployment: false,
  })

  if ((await beets.owner()) !== address) {
    // Transfer BEETS Ownership to Chef
    console.log("Transfer Beets Ownership to Chef")
    await (await beets.transferOwnership(address)).wait()
  }

  const masterChef = (await ethers.getContractAt("BeethovenxMasterChef", address)) as BeethovenxMasterChef
  if ((await masterChef.owner()) !== timelock.address) {
    // Transfer ownership of MasterChef to timelock
    console.log("Transfer ownership of MasterChef to Timelock")
    await (await masterChef.transferOwnership(timelock.address)).wait()
  }
}
