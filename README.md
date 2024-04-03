![Valantis](img/Valantis_Banner.png)

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

Contains source code of the smart contracts (excluding `/mocks` folders). Number of lines of code:

```
cloc src --not-match-d=mocks
```

**ALM:** Liquidity Module (LM) implementations, which are custom DEX logic contracts written in a modular way. It containes structs and interface which will need to be implemented by ALM.

**governance:** Contracts which are relevant in the context of the Valantis DAO, token, Gauges, Governance Escrow and its middlewares, and token emission mechanisms to eligible pools and ALMs. This is described in more detail in the white-paper. Currently contains only interface for AuctionController.

**libraries:** Various helper libraries used in other folders.

**oracles:** Contains interface for Oracle Module. There are two types, Universal and Sovereign, one of each type of pool.

**pools:** Implementation of Sovereign and Universal pools, the core backbone of Valantis that hosts all Modules, including LM, Swap Fee and Oracle modules.

**protocol-factory:** Holds the official addresses of the most important core contract factories in the protocol, including: Universal and Sovereign Pool factories, LM factories (one for each LM design), Swap Fee Module factories, Universal and Sovereign Oracle factories, Universal and Sovereign Gauge factories, etc, as well as respective deployments from within those factories. Valantis DAO will be able to add or remove certain addresses in this whitelist.

**swap-fee-modules:** Swap Fee module interface, which can be implemented and then plugged into Sovereign or Universal pools. Currently only contains a Swap Fee Module whose fixed swap fee is configurable by a designated address.

**utils:** Utils contracts which can be extended or used as library by main contracts.

**mocks:** Mock contracts used to simulate different behaviour for different components, used in tests.

### test

All relevent tests for contracts in src are in this folder

**base:** Base contracts for a respective contract, which are extended in concrete/fuzz/invariant tests for respective contracts. They contain helper internal functions to help in testing.

**helpers:** Helper contracts for mock contracts, to enable interacting with mock contracts. It is recommended to use respective helper contract to interact with mocks.

**deployers:** Deployer contract for respective contract, containing function for deploying target contract, this needs to be extended by test contract which wants to use or test target contract.

**libraries:** Tests for library contracts. It contains fuzz and concrete tests, both for target library.

**concrete:** Concrete tests are used to unit test target contract with hard coded values.

**fuzz:** Fuzz tests are used to test public functions in target contracts like Universal Pool and Sovereign Pool.

**integration:** Integration tests are used to test deployment and test basic functions of target contracts on mainnet fork, using real tokens.

**invariant:** Invariant tests are use to test for certain invariant for target contract. Currently only covers Sovereign Pool.
