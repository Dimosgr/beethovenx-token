import { HardhatRuntimeEnvironment } from "hardhat/types"
import { BeethovenxToken } from "../types"
import { bn } from "../utils/bn"

export default async function ({ ethers, getNamedAccounts, deployments }: HardhatRuntimeEnvironment) {
  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()

  const { address } = await deploy("BeethovenxToken", {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    contract: "contracts/BeethovenxToken.sol:BeethovenxToken",
  })

  const beets = (await ethers.getContractAt("contracts/BeethovenxToken.sol:BeethovenxToken", address)) as BeethovenxToken

  const partnershipFundAddress = process.env.PARTNERSHIP_FUND_ADDRESS!
  // 7% of total supply
  const strategicPartnershipFunds = bn(17_500_000)

  const teamFundAddress = process.env.TEAM_FUND_ADDRESS!
  // 13% of total supply
  const teamFund = bn(32_500_000)

  // 2% of total supply
  const lbpFunds = bn(5_000_000)

  if ((await beets.balanceOf(partnershipFundAddress)).eq(0)) {
    console.log(
      `minting strategic partnership funds '${strategicPartnershipFunds}' to strategic partnership address '${partnershipFundAddress}'`
    )
    await beets.mint(partnershipFundAddress, strategicPartnershipFunds)
  }

  if ((await beets.balanceOf(teamFundAddress)).eq(0)) {
    console.log(`minting team funds '${teamFund}' to team vesting contract address '${teamFundAddress}'`)
    await beets.mint(teamFundAddress, teamFund)
    console.log(`minting lbp funds '${lbpFunds}' to lbp address '${teamFundAddress}'`)
    await beets.mint(teamFundAddress, lbpFunds)
  }
}
