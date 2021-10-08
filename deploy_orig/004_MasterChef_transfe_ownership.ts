import { bn } from "../test/utilities"
import { HardhatRuntimeEnvironment } from "hardhat/types"
import { BeethovenxMasterChef, BeethovenxToken, Timelock } from "../types"

export default async function ({ ethers, deployments, getNamedAccounts, network }: HardhatRuntimeEnvironment) {
  const timelockDeployment = await deployments.get("Timelock")
  const timelock: Timelock = (await ethers.getContractAt("Timelock", timelockDeployment.address)) as Timelock

  const masterChef = (await ethers.getContractAt(
    "contracts/BeethovenxMasterChef.sol:BeethovenxMasterChef",
    "0x8166994d9ebBe5829EC86Bd81258149B87faCfd3"
  )) as BeethovenxMasterChef
  if ((await masterChef.owner()) !== timelock.address) {
    // Transfer ownership of MasterChef to timelock
    console.log("Transfer ownership of MasterChef to Timelock")
    await (await masterChef.transferOwnership(timelock.address)).wait()
  }
}
