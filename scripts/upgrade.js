const { ethers, upgrades } = require("hardhat");
async function main() {
  const MetafluenceV2 = await ethers.getContractFactory("MetafluenceV2");

  const metafluenceV2 = await upgrades.upgradeProxy(
    "0xb20b17a146D0CeAAAeC707a3703d790139f747bf",
    MetafluenceV2
  );
  await metafluenceV2.deployed();
  console.log(
    `Contract {${metafluenceV2.address}} upgraded! ✨`,
    metafluenceV2.address
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
