const { ethers, upgrades } = require("hardhat");
async function main() {
  const Collaborators = await ethers.getContractFactory("Collaborators");

  const collaborators = await upgrades.deployProxy(Collaborators);
  // Start deployment, returning a promise that resolves to a contract object
  await collaborators.deployed();
  console.log("Contract deployed to address:", collaborators.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
