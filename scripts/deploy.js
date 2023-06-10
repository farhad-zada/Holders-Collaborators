const { ethers, upgrades } = require("hardhat");
async function main() {
  const Metafluence = await ethers.getContractFactory("Metafluence");

  const metafluence = await upgrades.deployProxy(Metafluence);
  // Start deployment, returning a promise that resolves to a contract object
  await metafluence.deployed();
  console.log("Contract deployed to address:", metafluence.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
