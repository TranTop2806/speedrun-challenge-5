# 💳 Challenge 5: Over-Collateralized Lending

This project is a solution for Challenge 5 of SpeedRunEthereum. It implements a decentralized lending protocol where users can borrow **$CORN** tokens by depositing **ETH** as collateral. The system ensures solvency through over-collateralization and a liquidation mechanism.

## 🔗 Links
- **Live Demo:** https://nextjs-70q6em9ev-tranvananhthu280604-gmailcoms-projects.vercel.app
- **Lending Contract (Sepolia):** https://sepolia.etherscan.io/address/0x193772a00a24e9d16dDBBBbA27BdB86D2C50B96d#code
- **Corn Token (Sepolia):** https://sepolia.etherscan.io/address/0x1C754A63003B9aA947afb1E2619E0410f5422467#code
- **CornDEX (Sepolia):** https://sepolia.etherscan.io/address/0x60B838165b651b3B52E49b36CaEE0DD181d14d8C#code
## 🛠 Project Mechanics

### 1. Collateral & Borrowing
- **Collateral:** Users deposit ETH.
- **Asset:** Users borrow $CORN tokens.
- **Collateral Ratio:** The system requires a **120%** collateralization ratio.
  - Formula: `(Collateral Value in CORN * 100) / Borrowed Amount >= 120`

### 2. Liquidation System
If the value of the ETH collateral drops (relative to CORN) and the ratio falls below 120%, the position becomes **Liquidatable**.
- **Liquidator Role:** Anyone can pay back the borrower's debt (in $CORN).
- **Reward:** The liquidator receives the equivalent ETH collateral plus a **10% Liquidation Reward**.
- **Result:** The protocol avoids bad debt, and the liquidator makes a profit.

## 💻 Smart Contracts

- **Lending.sol:** Core logic for depositing, borrowing, repaying, and liquidating.
- **Corn.sol:** The ERC20 token used as the borrowed asset.
- **CornDEX.sol:** Acts as both a decentralized exchange and an on-chain price oracle for the Lending contract.

## 🏃‍♂️ How to Run Locally

Prerequisites: Node.js (>= v18.17), Yarn, Git.

### 1. Clone & Install
```bash
git clone [https://github.com/TranTop2806/speedrun-challenge-5-lending.git](https://github.com/TranTop2806/speedrun-challenge-5-lending.git)
cd speedrun-challenge-5-lending
yarn install
```
### 2. Start Local Chain
In terminal 1
```bash
yarn chain
```
### 3. Deploy Contracts
In terminal 2:

```bash
yarn deploy
```
Note: The deploy script automatically funds the contracts and sets up initial liquidity.

### 4. Start Frontend
In terminal 3:

```bash
yarn start
```
Visit http://localhost:3000 to interact with the Lending Protocol.

### How to Test Liquidation (Locally)
Borrow:

- Deposit 10 ETH as collateral.

- Borrow 8,000 CORN (High leverage, close to the limit).

Manipulate Price:

- Open a new browser window (Incognito).

- Connect a different wallet.

- Use the CornDEX (Debug Tab) to Sell ETH for CORN.

- This lowers the price of ETH.

Liquidate:

- Check the Borrower's dashboard; the position should now be flagged as "Liquidatable" (< 120%).

- Use the second wallet to call liquidate() on the Borrower's address.

- Observe the Liquidator receiving ETH + 10% bonus.