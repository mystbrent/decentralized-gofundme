# Decentralized GoFundMe for Universities

This project implements a decentralized fundraising platform for universities using smart contracts on the Ethereum blockchain. It includes two main implementations: SimpleGoFundMe and StreamingGoFundMe, along with a UniversityRegistry contract for managing verified university addresses.

## Project Structure

- `contracts/`:
  - `SimpleGoFundMe.sol`: A basic implementation with a two-phase distribution model.
  - `StreamingGoFundMe.sol`: An advanced implementation using the Sablier protocol for streaming funds.
  - `UniversityRegistry.sol`: A registry for managing verified university addresses.
- `contracts/test/`:
  - `SimpleGoFundMe.t.sol`: Tests for the SimpleGoFundMe contract.
  - `StreamingGoFundMe.t.sol`: Tests for the StreamingGoFundMe contract.
- `scripts/`:
  - `DeploySimpleGoFundMe.s.sol`: Deployment script for SimpleGoFundMe and UniversityRegistry.

## Key Features

- Stablecoin donations
- University verification through a registry
- Two-phase distribution model (SimpleGoFundMe)
- Streaming funds using Sablier protocol (StreamingGoFundMe)
- Voting mechanism for fund cancellation
- Platform fee collection

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
- [Node.js](https://nodejs.org/) and npm (for running scripts)

## Setup

1. Clone the repository:
   ```
   git clone https://github.com/your-username/defi-gofundme.git
   cd defi-gofundme
   ```

2. Install dependencies:
   ```
   forge install
   ```

3. Set up environment variables:
   Create a `.env` file in the project root and add the following:
   ```
   PRIVATE_KEY=your_private_key_here
   ETH_RPC_URL=your_ethereum_rpc_url_here
   ```

## Running Tests

To run the Foundry tests:

```
forge test
```

To run tests with verbose output:

```
forge test -vv
```

To run a specific test file:

```
forge test --match-path contracts/test/SimpleGoFundMe.t.sol
```

## Deployment

To deploy the SimpleGoFundMe contract and UniversityRegistry:

```
forge script scripts/DeploySimpleGoFundMe.s.sol --rpc-url $ETH_RPC_URL --broadcast --verify -vvvv
```

Make sure to replace `$ETH_RPC_URL` with your actual Ethereum RPC URL or use the one from your `.env` file.

## Contract Interactions

After deployment, you can interact with the contracts using tools like `cast` or by writing additional scripts.

Example of donating using `cast`:

```
cast send --private-key $PRIVATE_KEY $GOFUNDME_ADDRESS "donate(uint256)" 1000000000000000000 --rpc-url $ETH_RPC_URL
```

Replace `$GOFUNDME_ADDRESS` with the actual deployed contract address.

## Security Considerations

- Ensure proper access control for admin functions.
- Thoroughly test all voting and fund distribution mechanisms.
- Consider professional audits before mainnet deployment.

## Contributing

Contributions are welcome! Please fork the repository and create a pull request with your changes.

## License

This project is licensed under the MIT License.
