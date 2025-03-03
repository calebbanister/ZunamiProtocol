import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';

import 'hardhat-contract-sizer';
import 'hardhat-deploy';
import 'hardhat-gas-reporter';
import 'solidity-coverage';

import 'dotenv/config';

import { HardhatUserConfig } from 'hardhat/types';

const config: HardhatUserConfig = {
    defaultNetwork: 'hardhat',
    gasReporter: {
        currency: 'USD',
        coinmarketcap: process.env.COINMARKETCAP_API_KEY,
        showTimeSpent: true,
        enabled: true,
        outputFile: './gas_report',
    },
    paths: {
        sources: './contracts',
        tests: './test',
        artifacts: './artifacts',
        cache: './cache',
    },
    networks: {
        hardhat: {
            forking: {
                url: `${process.env.ETH_NODE_API_KEY}`,
                blockNumber: 15012681,
            },
            accounts: [
                // 5 accounts with 10^14 ETH each
                // Addresses:
                //   0x186e446fbd41dD51Ea2213dB2d3ae18B05A05ba8
                //   0x6824c889f6EbBA8Dac4Dd4289746FCFaC772Ea56
                //   0xCFf94465bd20C91C86b0c41e385052e61ed49f37
                //   0xEBAf3e0b7dBB0Eb41d66875Dd64d9F0F314651B3
                //   0xbFe6D5155040803CeB12a73F8f3763C26dd64a92
                {
                    privateKey:
                        '0xf269c6517520b4435128014f9c1e50c1c498374a7f5143f035bfb32153f3adab',
                    balance: '100000000000000000000000000000000',
                },
                {
                    privateKey:
                        '0xca3547a47684862274b476b689f951fad53219fbde79f66c9394e30f1f0b4904',
                    balance: '100000000000000000000000000000000',
                },
                {
                    privateKey:
                        '0x4bad9ef34aa208258e3d5723700f38a7e10a6bca6af78398da61e534be792ea8',
                    balance: '100000000000000000000000000000000',
                },
                {
                    privateKey:
                        '0xffc03a3bd5f36131164ad24616d6cde59a0cfef48235dd8b06529fc0e7d91f7c',
                    balance: '100000000000000000000000000000000',
                },
                {
                    privateKey:
                        '0x380c430a9b8fa9cce5524626d25a942fab0f26801d30bfd41d752be9ba74bd98',
                    balance: '100000000000000000000000000000000',
                },
            ],
            allowUnlimitedContractSize: false,
            blockGasLimit: 40000000,
            gas: 40000000,
            gasPrice: 'auto',
            loggingEnabled: false,
        },
        mainnet: {
            url: `${process.env.ETH_NODE_API_KEY}`,
            chainId: 1,
            gas: 'auto',
            gasMultiplier: 1.2,
            gasPrice: 10000000000,
            accounts: [`${process.env.PRIVATE_KEY}`],
            loggingEnabled: true,
        },
        polygon: {
            url: `${process.env.POLYGON_NODE_API_KEY}`,
            chainId: 137,
            accounts: [`${process.env.PRIVATE_KEY}`],
            gas: 'auto',
            gasMultiplier: 1.2,
            gasPrice: 50000000000,
            loggingEnabled: true,
        },
        bsc: {
            url: `${process.env.BINANCE_NODE_API_KEY}`,
            chainId: 56,
            accounts: [`${process.env.PRIVATE_KEY}`],
            gas: 'auto',
            gasMultiplier: 1.2,
            gasPrice: 5000000000,
            loggingEnabled: true,
        },
        development: {
            url: 'http://127.0.0.1:8545',
            gas: 12400000,
            timeout: 1000000,
        },
    },
    solidity: {
        compilers: [
            {
                version: '0.8.15',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    mocha: {
        timeout: 500000,
    },
    etherscan: {
        // apiKey: `${process.env.BSCSCAN_API_KEY}`,
        apiKey: `${process.env.ETHERSCAN_API_KEY}`,
    },
};

export default config;
