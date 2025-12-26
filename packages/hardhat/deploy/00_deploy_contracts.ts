import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { Contract } from "ethers";

const deployContracts: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  await deploy("Corn", {
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
  });
  const cornToken = await hre.ethers.getContract<Contract>("Corn", deployer);

  await deploy("CornDEX", {
    from: deployer,
    args: [await cornToken.getAddress()],
    log: true,
    autoMine: true,
  });
  const cornDEX = await hre.ethers.getContract<Contract>("CornDEX", deployer);

  const lendingDeploy = await deploy("Lending", {
    from: deployer,
    args: [await cornDEX.getAddress(), await cornToken.getAddress()],
    log: true,
    autoMine: true,
  });
  const lending = await hre.ethers.getContract<Contract>("Lending", deployer);

  const movePrice = await deploy("MovePrice", {
    from: deployer,
    args: [await cornDEX.getAddress(), await cornToken.getAddress()],
    log: true,
    autoMine: true,
  });

  if (hre.network.name === "localhost") {
    console.log("Configuring for Localhost...");
    
    await hre.ethers.provider.send("hardhat_setBalance", [
      movePrice.address,
      `0x${hre.ethers.parseEther("10000").toString(16)}`,
    ]);
    await cornToken.mintTo(movePrice.address, hre.ethers.parseEther("10000"));

    await cornToken.mintTo(await lending.getAddress(), hre.ethers.parseEther("10000"));

    await cornToken.mintTo(deployer, hre.ethers.parseEther("10000"));
    
    await cornToken.approve(await cornDEX.getAddress(), hre.ethers.parseEther("1000"));
    await cornDEX.init(hre.ethers.parseEther("1000"), { value: hre.ethers.parseEther("1") }); // Ratio 1 ETH : 1000 CORN
  } 
  
  else {
    console.log("Configuring for Public Network (Sepolia)...");
    
    // 1. Fund Lending Contract (So users can borrow)
    // We transfer 100 CORN from deployer to Lending contract
    console.log("Funding Lending Contract...");
    try {
        await cornToken.transfer(await lending.getAddress(), hre.ethers.parseEther("100"));
    } catch (e) {
        console.log("Could not fund Lending contract (Check deployer balance)");
    }

    // 2. Initialize DEX (Set Price)
    console.log("Initializing DEX Liquidity...");
    try {
        await cornToken.approve(await cornDEX.getAddress(), hre.ethers.parseEther("10"));
        // Init with: 0.01 ETH and 10 CORN => Price: 1 ETH = 1000 CORN
        await cornDEX.init(hre.ethers.parseEther("10"), { value: hre.ethers.parseEther("0.01") });
    } catch (e) {
         console.log("DEX might already be initialized or insufficient funds");
    }
  }
};

export default deployContracts;
deployContracts.tags = ["Lending"];