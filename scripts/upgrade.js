const { ethers, upgrades } = require("hardhat");
async function main() {
  const CollaboratorsV2 = await ethers.getContractFactory("CollaboratorsV2");

  const collaboratorsV2 = await upgrades.upgradeProxy(
    "0xb20b17a146D0CeAAAeC707a3703d790139f747bf",
    CollaboratorsV2
  );
  await collaboratorsV2.deployed();
  console.log(
    `Contract {${collaboratorsV2.address}} upgraded! ✨`,
    collaboratorsV2.address
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
