async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  const MeSa = await ethers.getContractFactory("MeSa");
  const mesa = await MeSa.deploy("1000000000000000000000000"); // 1M tokens with 18 decimals

  console.log("MeSa deployed to:", mesa.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
