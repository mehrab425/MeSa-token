const { expect } = require("chai");

describe("MeSa Token", function () {
  it("Should assign the total supply to the deployer", async function () {
    const [owner] = await ethers.getSigners();
    const MeSa = await ethers.getContractFactory("MeSa");
    const mesa = await MeSa.deploy("1000000000000000000000000");

    const ownerBalance = await mesa.balanceOf(owner.address);
    expect(await mesa.totalSupply()).to.equal(ownerBalance);
  });
});
