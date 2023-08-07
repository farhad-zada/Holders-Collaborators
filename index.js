const ethers = require("ethers")
require("dotenv").config()

async function main(id) {
    let mumbai = new ethers.JsonRpcProvider(process.env.MUMBAI)
    let sepolia = new ethers.JsonRpcProvider(process.env.SEPOLIA)
    let abi = [
        "event Sent(uint256 messageId,uint256 chainId,address destination,address from,address to,uint256 amount)",
        "function accept(uint256 messageId,uint256 chainId,address source,address from,address to,uint256 amount)public",
    ]
    const bridgeDetails = {
        80001: {
            name: "Polygon Mumbai",
            signer: new ethers.Wallet(process.env.PKEY, mumbai),
            bridgeContract: new ethers.Contract(
                process.env.CON_MUMBAI,
                abi,
                mumbai
            ),
        },
        11155111: {
            name: "Ethereum Sepolia",
            signer: new ethers.Wallet(process.env.PKEY, sepolia),
            bridgeContract: new ethers.Contract(
                process.env.CON_SEPOLIA,
                abi,
                sepolia
            ),
        },
    }

    console.log(`\nListening to ${id}...🤫\n`)

    bridgeDetails[id].bridgeContract.on(
        "Sent",
        async (messageId, chainId, destination, from, to, amount, event) => {
            console.log(
                `Event Received:\n` +
                    `Message ID: ${messageId.toString()}\n` +
                    `Chain ID: chainId.toString()\n` +
                    `Destination: ${destination}\n` +
                    `From: ${from}\n` +
                    `To: ${to}\n` +
                    `Amount: ${amount.toString()}\n`
            )

            const txData = bridgeDetails[chainId][
                "bridgeContract"
            ].interface.encodeFunctionData("accept", [
                messageId,
                chainId,
                destination,
                from,
                to,
                amount,
            ])

            let trxParams = {
                to: destination,
                data: txData,
                gasPrice: ethers.parseUnits("20", "gwei"),
                gasLimit: 300000,
            }

            const tx = await bridgeDetails[chainId].signer.sendTransaction(
                trxParams
            )
            await tx.wait(1)
            console.log(
                `Tokens have been moved:\n` +
                    `From: ${bridgeDetails[id].name}\n` +
                    `To: ${bridgeDetails[chainId].name}\n` +
                    `Status: Success 🍺\n\n` +
                    `Source trx hash: ${event.log.transactionHash}\n` +
                    `Destination trx hash: ${tx.hash}\n\n` +
                    `From: ${from}\n` +
                    `To: ${to}\n`
            )
        }
    )
}

main(80001).catch((err) => {
    console.log(err)
    process.exitCode = 1
})
main(11155111).catch((err) => {
    console.log(err)
    process.exitCode = 1
})
