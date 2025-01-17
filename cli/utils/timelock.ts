import moment from "moment"
import { network } from "hardhat"
import { StoredTimelockTransaction } from "../types"

const isMainnet = network.name === process.env.MAINNET

const storedTransactions: Record<
  string,
  StoredTimelockTransaction
  // eslint-disable-next-line @typescript-eslint/no-var-requires
> = require(`../../.timelock/transactions.${network.name}.json`)

export const timelockQueueQuestions = [
  {
    name: "timelock",
    type: "confirm",
    message: "queue on timelock",
  },
  // {
  //   name: 'tla',
  //   message: 'Timelock transaction type',
  //   type: 'list',
  //   when: (answers: any) => answers.timelock,
  //   choices: ['queue', 'execute'],
  //   default: 'queue',
  // },
  {
    name: "eta",
    type: "number",
    message: `eta when to be executed on timelock (default: ${isMainnet ? "6h + 10min" : "12mins"})`,
    when: (answers: any) => answers.timelock,
    default: isMainnet
      ? moment()
          .add(6 * 60 + 10, "minutes")
          .unix()
      : moment().add(12, "minutes").unix(),
  },
]

export function getTimelockTransactionIds(onlyExecutable = true) {
  if (onlyExecutable) {
    return Object.keys(storedTransactions).filter((transactionId) => {
      return !storedTransactions[transactionId].executed && moment().isSameOrAfter(moment.unix(storedTransactions[transactionId].eta))
    })
  } else {
    return Object.keys(storedTransactions)
  }
}

export function getTimelockTransactions() {
  return Object.keys(storedTransactions)
    .map(
      (transactionId) =>
        `[${transactionId}][${moment.unix(storedTransactions[transactionId].eta)}]  - ${
          storedTransactions[transactionId].targetContract.name
        } - ${storedTransactions[transactionId].targetContract.address} - ${
          storedTransactions[transactionId].targetFunction.identifier
        } - ${JSON.stringify(storedTransactions[transactionId].targetFunction.args)} - executed: ${storedTransactions[transactionId].executed} ${
          storedTransactions[transactionId].executeTxHash ?? ""
        }`
    )
    .join("\n")
}
