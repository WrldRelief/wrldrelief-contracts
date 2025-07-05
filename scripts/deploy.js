const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("Starting deployment of WRLD Relief smart contracts...");
  
  // Get deployer account
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying contracts with the account: ${deployer.address}`);
  console.log(`Account balance: ${(await deployer.getBalance()).toString()}`);
  
  // Record deployed contract addresses
  const deployedContracts = {};
  
  try {
    // 1. Deploy DisasterRegistry
    console.log("\n1. Deploying DisasterRegistry...");
    const DisasterRegistry = await ethers.getContractFactory("DisasterRegistry");
    const disasterRegistry = await upgrades.deployProxy(DisasterRegistry, [], { initializer: 'initialize' });
    await disasterRegistry.deployed();
    deployedContracts.DisasterRegistry = disasterRegistry.address;
    console.log(`DisasterRegistry deployed at: ${disasterRegistry.address}`);
    
    // 2. Deploy WrldReliefUser
    console.log("\n2. Deploying WrldReliefUser...");
    const WrldReliefUser = await ethers.getContractFactory("WrldReliefUser");
    const wrldReliefUser = await upgrades.deployProxy(WrldReliefUser, [], { initializer: 'initialize' });
    await wrldReliefUser.deployed();
    deployedContracts.WrldReliefUser = wrldReliefUser.address;
    console.log(`WrldReliefUser deployed at: ${wrldReliefUser.address}`);
    
    // 3. Deploy WRLFGovernanceToken with a placeholder treasury address (can be updated later)
    console.log("\n3. Deploying WRLFGovernanceToken...");
    const WRLFGovernanceToken = await ethers.getContractFactory("WRLFGovernanceToken");
    // Using deployer address as temporary treasury, can be updated later
    const wrlfGovernanceToken = await upgrades.deployProxy(WRLFGovernanceToken, [deployer.address], { initializer: 'initialize' });
    await wrlfGovernanceToken.deployed();
    deployedContracts.WRLFGovernanceToken = wrlfGovernanceToken.address;
    console.log(`WRLFGovernanceToken deployed at: ${wrlfGovernanceToken.address}`);
    
    // 4. Deploy WrldReliefSBT
    console.log("\n4. Deploying WrldReliefSBT...");
    const WrldReliefSBT = await ethers.getContractFactory("WrldReliefSBT");
    const wrldReliefSBT = await upgrades.deployProxy(WrldReliefSBT, [], { initializer: 'initialize' });
    await wrldReliefSBT.deployed();
    deployedContracts.WrldReliefSBT = wrldReliefSBT.address;
    console.log(`WrldReliefSBT deployed at: ${wrldReliefSBT.address}`);
    
    // 5. Deploy Campaign implementation (not initialized)
    console.log("\n5. Deploying Campaign implementation...");
    const Campaign = await ethers.getContractFactory("Campaign");
    const campaignImpl = await Campaign.deploy();
    await campaignImpl.deployed();
    deployedContracts.CampaignImplementation = campaignImpl.address;
    console.log(`Campaign implementation deployed at: ${campaignImpl.address}`);
    
    // 6. Deploy CampaignFactory
    console.log("\n6. Deploying CampaignFactory...");
    const CampaignFactory = await ethers.getContractFactory("CampaignFactory");
    const campaignFactory = await upgrades.deployProxy(
      CampaignFactory, 
      [
        campaignImpl.address,
        wrldReliefUser.address,
        disasterRegistry.address
      ], 
      { initializer: 'initialize' }
    );
    await campaignFactory.deployed();
    deployedContracts.CampaignFactory = campaignFactory.address;
    console.log(`CampaignFactory deployed at: ${campaignFactory.address}`);
    
    // 7. Set up permissions and roles
    console.log("\n7. Setting up permissions and roles...");
    
    // Grant MINTER_ROLE to CampaignFactory for SBT
    const MINTER_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("MINTER_ROLE"));
    await wrldReliefSBT.grantRole(MINTER_ROLE, campaignFactory.address);
    console.log(`Granted MINTER_ROLE to CampaignFactory on WrldReliefSBT`);
    
    // Grant ADMIN_ROLE to CampaignFactory for WrldReliefUser
    const ADMIN_ROLE = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ADMIN_ROLE"));
    await wrldReliefUser.grantRole(ADMIN_ROLE, campaignFactory.address);
    console.log(`Granted ADMIN_ROLE to CampaignFactory on WrldReliefUser`);
    
    // Save deployment information
    const deploymentInfo = {
      network: network.name,
      deployer: deployer.address,
      contracts: deployedContracts,
      timestamp: new Date().toISOString()
    };
    
    const deploymentPath = path.join(__dirname, "../deployment-info.json");
    fs.writeFileSync(
      deploymentPath,
      JSON.stringify(deploymentInfo, null, 2)
    );
    console.log(`\nDeployment information saved to ${deploymentPath}`);
    
    console.log("\nDeployment completed successfully!");
    console.log("\nNext steps:");
    console.log("1. Set up USDC token address for Campaign contracts");
    console.log("2. Update treasury address for WRLFGovernanceToken if needed");
    console.log("3. Assign appropriate roles to users and administrators");
    
  } catch (error) {
    console.error("Deployment failed:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
