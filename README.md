# alpha-contract

## Install

### direnv

Recommend **direnv**

Mac OS

```
brew install direnv
```

Other OS

```
git clone https://github.com/direnv/direnv
cd direnv
sudo make install
```

Copy to **.envrc** and setup

```
cp envrc.sample .envrc
direnv allow
```

Passed path to node_modules, you don't need to use "npx"

### npm

To run hardhat script

```
npm install
```

### foundry

To install Foundry for Testing (assuming a Linux or macOS system)

```
curl -L https://foundry.paradigm.xyz | bash
```

This will download foundryup. To start Foundry, run

```
foundryup
```

To install dependencies

```
forge install
```

## Usage

Testing

with forking Arbitrum

```
forge test -vv --fork-url ${RPC_ARB} --fork-block-number ${BLOCK_ARB} --no-match-path 'test/foundry/tmp/*'
```
