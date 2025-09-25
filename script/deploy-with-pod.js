#!/usr/bin/env node
/*
  Foundry-driven deployment helper that mirrors scripts/deploy.js while
  leveraging the Pod SDK for transaction submission.

  Required env vars:
    POD_RPC_URL        - target RPC endpoint
    POD_PRIVATE_KEY    - hex private key (0x...)
    POD_GUARDIAN_ADDRESS (optional) - guardian wallet, defaults to deployer
*/

const fs = require('fs');
const path = require('path');
const { Interface, JsonRpcProvider, Wallet } = require('ethers');
const {
  PodProviderBuilder,
  PodTransactionRequest
} = require('pod-sdk');

function createPodTransactionRequest(init) {
  if (PodTransactionRequest && typeof PodTransactionRequest.from === 'function') {
    return PodTransactionRequest.from(init);
  }
  return new PodTransactionRequest(init);
}

async function buildSigner(rpcUrl, privateKey) {
  if (!rpcUrl) {
    throw new Error('POD_RPC_URL is required');
  }
  if (!privateKey) {
    throw new Error('POD_PRIVATE_KEY is required');
  }

  // Pod SDK provider handles signing + transport while enforcing legacy mode.
  const podProvider = await new PodProviderBuilder()
    .withRpcUrl(rpcUrl)
    .withLegacyTransactions()
    .build();

  const provider = new JsonRpcProvider(rpcUrl);
  const wallet = new Wallet(privateKey, provider);
  return { podProvider, provider, wallet };
}

function readArtifact(projectRoot, relativePath, contractName) {
  const artifactPath = path.join(
    projectRoot,
    'out',
    `${relativePath}.sol`,
    `${contractName}.json`
  );
  if (!fs.existsSync(artifactPath)) {
    throw new Error(`Missing artifact for ${contractName} at ${artifactPath}`);
  }
  return JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
}

function buildDeploymentRequest(artifact, constructorArgs, gasPrice) {
  const iface = new Interface(artifact.abi);
  const encodedArgs = iface.encodeDeploy(constructorArgs ?? []);
  const bytecode = artifact.bytecode && artifact.bytecode.object;
  if (!bytecode || bytecode === '0x') {
    throw new Error('Artifact does not contain bytecode');
  }

  const data = `${bytecode}${encodedArgs.slice(2)}`;
  const requestInit = {
    to: undefined,
    data,
    legacy: true,
    value: 0n
  };

  if (gasPrice) {
    requestInit.gasPrice = BigInt(gasPrice);
  }

  return createPodTransactionRequest(requestInit);
}

async function broadcastDeployment(name, request, wallet, provider, podProvider) {
  const nonce = await provider.getTransactionCount(wallet.address);
  const gasPrice = request.gasPrice ?? (await provider.getGasPrice());
  const tx = {
    to: request.to,
    data: request.data,
    gasLimit: request.gasLimit ?? 6_000_000n,
    gasPrice,
    nonce,
    value: request.value ?? 0n,
    type: 0
  };

  const signedTx = await wallet.signTransaction(tx);
  const broadcastFn =
    podProvider.broadcastTransaction ||
    podProvider.sendRawTransaction ||
    podProvider.sendTransaction;
  if (typeof broadcastFn !== 'function') {
    throw new Error('Pod provider cannot broadcast raw transactions');
  }

  const receipt = await broadcastFn.call(podProvider, signedTx);
  if (!receipt || !receipt.contractAddress) {
    throw new Error(`Failed to deploy ${name}`);
  }
  return receipt.contractAddress;
}

async function main() {
  const projectRoot = process.argv[2] || process.cwd();
  const rpcUrl = process.env.POD_RPC_URL;
  const privateKey = process.env.POD_PRIVATE_KEY;
  const guardianEnv = process.env.POD_GUARDIAN_ADDRESS;

  const { podProvider, provider, wallet } = await buildSigner(rpcUrl, privateKey);
  const deployer = await wallet.getAddress();
  const guardian = guardianEnv && guardianEnv !== '' ? guardianEnv : deployer;

  const gasPrice = await provider.getGasPrice();

  const treasuryArtifact = readArtifact(
    projectRoot,
    'core/ProtocolTreasury',
    'ProtocolTreasury'
  );
  const treasuryRequest = buildDeploymentRequest(
    treasuryArtifact,
    [deployer, guardian],
    gasPrice
  );
  const treasuryAddress = await broadcastDeployment(
    'ProtocolTreasury',
    treasuryRequest,
    wallet,
    provider,
    podProvider
  );

  const dexFactoryArtifact = readArtifact(projectRoot, 'dex/DEXFactory', 'DEXFactory');
  const dexFactoryRequest = buildDeploymentRequest(
    dexFactoryArtifact,
    [treasuryAddress, deployer],
    gasPrice
  );
  const dexFactoryAddress = await broadcastDeployment(
    'DEXFactory',
    dexFactoryRequest,
    wallet,
    provider,
    podProvider
  );

  const dexRouterArtifact = readArtifact(projectRoot, 'dex/DEXRouter', 'DEXRouter');
  const dexRouterRequest = buildDeploymentRequest(
    dexRouterArtifact,
    [dexFactoryAddress],
    gasPrice
  );
  const dexRouterAddress = await broadcastDeployment(
    'DEXRouter',
    dexRouterRequest,
    wallet,
    provider,
    podProvider
  );

  const launchpadArtifact = readArtifact(
    projectRoot,
    'core/LaunchpadFactory',
    'LaunchpadFactory'
  );
  const launchpadRequest = buildDeploymentRequest(
    launchpadArtifact,
    [deployer, dexFactoryAddress, dexRouterAddress, guardian],
    gasPrice
  );
  const launchpadAddress = await broadcastDeployment(
    'LaunchpadFactory',
    launchpadRequest,
    wallet,
    provider,
    podProvider
  );

  const launchpadInterface = new Interface(launchpadArtifact.abi);
  const treasuryCallData = launchpadInterface.encodeFunctionData('treasury');
  const treasuryCall = await provider.call({
    to: launchpadAddress,
    data: treasuryCallData
  });
  const parsedTreasury = launchpadInterface.decodeFunctionResult(
    'treasury',
    treasuryCall
  )[0];

  const deployment = {
    dexFactory: dexFactoryAddress,
    router: dexRouterAddress,
    launchpad: launchpadAddress,
    treasury: parsedTreasury
  };

  const outputPath = path.join(projectRoot, 'deployment-foundry.json');
  fs.writeFileSync(outputPath, `${JSON.stringify(deployment, null, 2)}\n`);
  console.log('Deployment complete via Foundry/Pod SDK:', deployment);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
