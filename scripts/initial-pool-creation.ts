import { network } from "hardhat"
import { stdout } from "../cli/utils/stdout"
import { printNetwork } from "../cli/utils/network"
import { addMasterChefPool, listPools } from "../cli/contract-interactions/masterchef"

type PoolConfig = {
  lpAddress: string
  allocationPoints: number
}

const zeroAddress = "0x0000000000000000000000000000000000000000"

const intialPools: Record<number, PoolConfig[]> = {
  //opera
  250: [],
  // rinkeby
  4: [
    {
      lpAddress: "0x33276D43aDA054a281d40a11d48310Cdc0156fc2",
      allocationPoints: 10,
    },
    {
      lpAddress: "0x86b03134Ea51903a692aAE8808ce96554012C5bd",
      allocationPoints: 10,
    },
    {
      lpAddress: "0x864e386BBBb8b06cBf060fC0b7587aB5f40d5c9B",
      allocationPoints: 10,
    },
    {
      lpAddress: "0xf453D2AD5cEf4e3f1FD4B81b2d5421a412Fd311f",
      allocationPoints: 10,
    },
  ],
}

async function setupInitialFarmPools() {
  await printNetwork()
  stdout.printInfo(`Setting up initial pools`)
  const pools = intialPools[network.config.chainId!]

  for (const pool of pools) {
    stdout.printStep(`Adding pool to master chef for LP ${pool.lpAddress} with allocation points ${pool.allocationPoints}`)
    const tx = await addMasterChefPool(pool.allocationPoints, pool.lpAddress, zeroAddress)
    stdout.printStepDone(`done with tx ${tx}`)
  }
  stdout.printInfo("Listing all pools: \n")
  await listPools()
}

setupInitialFarmPools().catch((error) => {
  stdout.printError(error.message, error)
  process.exit(1)
})
