# Valantis

Implementation of the Valantis Core smart contracts in Solidity.

## Setting up Foundry

We use Foundry as our Solidity development framework. See [here](https://book.getfoundry.sh/getting-started/installation) for installation instructions, docs and examples.

Once installed, build the project:

```
forge build
```

Install dependencies:

```
forge install && yarn install
```

Tests:

To run foundry tests which included concrete tests and fuzz tests:

```
forge test
```

To run integration tests, first copy `.env.example` to `.env` :

```
cp .env.example .env
npx hardhat test
```

Docs:

```
forge doc --serve --port 8080
```

## Folder structure description

### lib:

Contains all smart contract external dependencies, installed via Foundry as git submodules.

### src

All relevant contracts to be audited are in src folder (excluding `/mocks` folders). Number of lines of code:

```
cloc src --not-match-d=mocks
```

**ALM:** Liquidity Module (LM) implementations, which are custom DEX logic contracts written in a modular way. It containes structs and interface which will need to be implemented by ALM.

**governance:** Contracts which are relevant in the context of the Valantis DAO, token, Gauges, Governance Escrow and its middlewares, and token emission mechanisms to eligible pools and ALMs. This is described in more detail in the white-paper. Currently contains only interface for AuctionController.

**libraries:** Various helper libraries used in other folders.

**oracles:** Contains interface for Oracle which can be implemented to be plugged in Sovereign Pool

**pools:** Implementation of Sovereign pool, the core backbone of Valantis that hosts all modules, including LM, Swap Fee and Oracle modules.

**protocol-factory:** Holds the official addresses of the most important core contract factories in the protocol, including: Universal and Sovereign Pool factories, LM factories (one for each LM design), Swap Fee Module factories, Universal and Sovereign Oracle factories, Universal and Sovereign Gauge factories, etc, as well as respective deployments from within those factories. Valantis DAO will be able to add or remove certain addresses in this whitelist.

**swap-fee-modules:** Swap Fee module interface, which can be implemented and then plugged into Sovereign pools. Only contains a swap fee module whose fixed swap fee is configurable by a designated address.

**utils:** Utils contracts which can be extended or used as library by main contracts
