# WRLD Relief Smart Contract System

This project is a Hardhat deployment environment for the WRLD Relief smart contract system.

## Project Structure

- `Campaign.sol`: Campaign contract
- `CampaignFactory.sol`: Campaign factory contract
- `DisasterRegistry.sol`: Disaster registry contract
- `WrldReliefSBT.sol`: SBT (Soulbound Token) contract
- `WrldReliefUser.sol`: User management contract
- `WRLFGovernanceToken.sol`: Governance token contract
- `scripts/deploy.js`: Script to deploy all contracts

## Installation and Setup

1. Install necessary packages:

```bash
npm install
```

2. Copy the `.env.example` file to create a `.env` file:

```bash
cp .env.example .env
```

3. Edit the `.env` file to set the required environment variables:
   - RPC URL
   - Private key
   - Other configuration values

## Compile Contracts

```bash
npx hardhat compile
```

## Deploy Contracts

### Deploy to Local Network

1. Start the local Hardhat network:

```bash
npx hardhat node
```

2. In a separate terminal, run the deployment script:

```bash
npm run deploy:local
```

### Deploy to Testnet

```bash
npm run deploy:testnet
```

### Deploy to Mainnet

```bash
npm run deploy:mainnet
```

## Deployment Order

Smart contracts are deployed in the following order:

1. DisasterRegistry
2. WrldReliefUser
3. WRLFGovernanceToken
4. WrldReliefSBT
5. Campaign (implementation)
6. CampaignFactory

Upon completion, deployment information is stored in the `deployment-info.json` file.

## Post-Deployment Configuration

1. Set the USDC token address
2. Update the Treasury address if necessary
3. Assign appropriate roles to users and administrators

## Caution

- Thoroughly test on the testnet before deploying to the mainnet.
- Keep the private key secure and never expose it.
- Ensure data preservation when upgrading contracts.
