Welcome to pod Documentation
pod is a programmable layer-one designed from first principles to enable internet-scale web3 applications. Traditional blockchains totally order transactions through consensus mechanisms, requiring multiple rounds of network communication and making them slow and expensive. pod doesn’t totally order transactions, allowing it to confirm transactions in one network round trip (<150ms) - the same speed as any traditional web2 client-server architecture.

pod doesn’t have blocks or chains. At a high level, transactions are streamed to a set of validators, which locally validate the transactions and stream the attestations back. Once the user receives a sufficient number of attestations, the transaction is finalised. Read more about the pod’s design here.

pod has a live devnet; you can view the live transactions in our explorer and find the network configuration and faucet here. pod supports EVMx, allowing developers to leverage their existing Ethereum developer toolchain. If you have experience building applications on Ethereum, this cheat sheet will help you get started with pod.


Devnet
Add devnet to your wallet and get test tokens.
Devnet
The pod devnet is a test network for developers to experiment with the pod network. It is designed to be a sandbox for testing and development purposes, allowing developers to build and test their applications without the need for real assets or transactions.

Name	pod	
RPC	https://rpc.v1.dev.pod.network	
Chain ID	1293	
Explorer	https://explorer.v1.pod.network	
EVM Version	Prague (Ethereum block 22,431,084, Released May 7th, 2025)	
native token pETH

Add network to wallet  
Go to Explorer  
Precompiles
Signature	Address	Description
requireQuorum(boolean)	0x4CF3F1637bfEf1534e56352B6ebAae243aF464c3	Like require but passes if supermajority agrees
external_call([uint256, [Transaction,bytes]])	0x8712E00C337971f876621faB9326908fdF330d77	Call a smart contract on another EVM-compatible chain
call_with_state([uint256, Header, EVMCall, EVMState])	0xb4bbff8874b41f97535bc8dafbaaff0dc5c72e5a	Simulate an EVM transaction execution given a particular initial state
We expect the devnet to have breaking changes or be reset (pruned completely) at any time.

how it works/
Partially Ordered Dataset
pod is a new layer-1 primitive that takes transactions as input and produces a log (sequence of transactions) as output. It is a service that receives unordered transactions submitted into the mempool and orders them into a log. Contrary to blockchains and other consensus protocols, pod does not provide a persistent total order of transactions. While it does give some order, this order is subject to change with time — transactions “wiggle” around their positions in a somewhat predictable fashion. Accepting this wiggle room allows for making a very performant system. In particular, pod is latency-optimal and throughput-optimal. To accomplish this, we first eliminate inter-validator communication. Instead, clients send transactions directly to all validators; each validator independently processes transactions and appends them to its log. Clients then receive and extract information from these logs. Check out the pod-core paper for detailed pseudo-code and formal analysis.


Figure 1 (consensus vs pod): Transactions in pod can wiggle but their bounds are known.
‍

This post provides a high-level overview of pod’s key components and design choices. As we roll out the protocol, we anticipate these systems will evolve (or completely change). We will release blogs that explain the concepts in depth and papers that formally analyze each component.

Key design principles:
Optimal Latency. Transactions are confirmed in one network round trip (~200ms). This confirmation latency is optimal because it hits the speed of light limit. The latency is the same as what you would expect when you interact with traditional Web2 (client ↔ server) architecture. Formally, we achieve liveness u equal to the physical network latency round-trip time 2δ in synchrony and eventual liveness in asynchrony.
Streaming. All aspects of our system are push rather than pull. Each node (full or light) connecting to a validator subscribes to a channel indicating what streams of data they’re interested in. The validator then sends the nodes the relevant data as soon as it is available. The same principle applies in the connection between a secondary and its validator or a client and a secondary (see below). This follows the classical design pattern of “publish/subscribe.” The way this is realized in practice is by using (web)sockets. This dictates a large part of our design, giving rise to ideas such as blocklessness. When you have blocks on a blockchain, you must wait for a block to appear in order to receive a transaction confirmation, adding artificial delay. Our streaming design allows us to confirm transactions as soon as they receive sufficient signatures.
Simplicity. pod-core uses a radically straightforward design, making it easy to implement, audit, and formally analyze. While it has many extensions enabling advanced behaviors, pod’s “consensus” core is just a few hundred lines of Rust code. The dependencies used in pod’s core are just hash functions and signatures—no zero knowledge, multiparty computation, or other moon math. pod’s extensions employ advanced cryptographic techniques to enable more powerful features on top, but the heart of the construction is very simple.
Scalability. pod borrows its design from traditional relational DBMS systems from the 80s, 90s, 00s, and 10s, before the Web3 era. These techniques are battle-tested but have not been designed to be byzantine-resilient. pod leverages these techniques to scale to Internet scale. Such structures include separating write from read validators (the primary–secondary paradigm), efficient caching and indexing, load balancing, and hot swapping. We’ve also borrowed techniques (such as Merkle Mountain Ranges and no validator-to-validator communication) from Certificate Transparency, a backbone behind the security of X509/HTTPS, which processes Internet-scale traffic.
Flexibility. A flexible design provides different guarantees to people with different needs. Some clients may favor safety over liveness, some may be on-chain, while others are off-chain. A small minority may believe in the security of TEEs. Our design is not tailored to a particular belief, but we allow these clients to interoperate with each other, each reaping their preferred benefits (as long as their beliefs correspond to reality).
Modularity. While pod’s design is simple (see above), it is a feature-rich system. To achieve this richness without sacrificing simplicity, each component of pod is designed to be stand-alone and provide a clean interface to its friends. One such example, pioneered by Celestia, is the separation of “consensus” from execution; consensus confirms transactions, whereas execution settles state.
Accountability. Every validator claim in pod is accountable — from the confirmation of a single transaction to the response to a light client query about a particular smart contract to the full log report provided to full nodes. This enables faulty validators to be slashed, giving rise to economic security.
Censorship Resistance. While liveness guarantees that every honest transaction is confirmed soon, censorship resistance imposes a shorter confirmation time frame in which honest transactions cannot be selectively censored; any censorship attack is forced to stall the whole system or confirm all honest transactions. In pod’s case, because we are leaderless and blockless, the stalling case never takes place, and we can guarantee liveness matching censorship resistance.
pod-core
(check out the paper for pseudo-code and formal analysis)

pod's core construction is simple and can be explained in just a couple of minutes. Its infrastructure consists of a set of active validators whose job is to record transactions. Validators do not talk to each other directly—this is exactly what makes pod so fast. The active validator set is known to the clients. Clients connect to these validators and send transactions to them that are eventually confirmed. Clients can then query the log from the validators to discover the confirmed transactions and their wiggle room.

Each validator maintains a local, totally ordered temporal log. A temporal log is a sequence of transactions, each associated with a timestamp. The timestamps have millisecond precision and must be non-decreasing. Each validator’s temporal log is its own local data structure and is unaffected by other validators’ logs. A client that wishes to write a transaction connects to all validators and sends them the transaction of interest. Whenever a validator receives a new transaction from a client, it appends it to its local log, together with the current timestamp based on its local clock. It then signs the transaction with the timestamp and hands it back to the client. The client receives the signed transaction and timestamp and validates the validator’s signature using its known public key. As soon as the client has collected a certain number of signatures from the validators (e.g., α = 2/3 of the validators), the client considers the transaction confirmed. The client associates the transaction with a timestamp, too: the median among the timestamps signed by the validators.

A full node that wishes to obtain a full picture of confirmed transactions reaches out to all the validators and requests their full log. Upon such a request, the validator returns the full log containing timestamped transactions, together with the current timestamp, all signed by the validator key. The node then considers any transaction with more than α signatures confirmed and assigns the median timestamp to it. The node orders the transactions using these median timestamps, which are the node’s log. Because different nodes may receive a response from a different subset of validators, they may not arrive at the same timestamp for a given transaction. That’s what gives rise to a transaction’s wiggle room. However, a node can find upper and lower bounds for that wiggle room, a parameter we call a transaction’s minimum and maximum temperature.


Figure 2 (transaction flow): The transaction flows from the client to the set of validators and back to client, requiring one network round trip end-to-end.
‍

In principle, you can see why this system is already capable of achieving optimal latency and throughput. To confirm a transaction, the client requires one roundtrip to the validators — achieving optimal latency. The number of transactions a validator can process in a unit of time is bounded by the bandwidth of the channel connecting the client to the validators, achieving optimal throughput. It is straightforward to see that no better performance can be achieved in any system that requires all validators to see all transactions (such as a blockchain system) because the system matches the physical limits of the validators’ capacity (if the requirement that all validators see all transactions is removed, we can achieve better bandwidth utilization).

Execution
Blockchain systems take the ordered set of confirmed transactions and deduce a state by applying them one on top of the other in the given order. This is referred to as state-machine replication. Current systems apply a global lock to the state machine, and the whole system must wait for the transaction to be applied before a future transaction can be processed, similar to a table-level lock in a traditional DBMS. In pod, we can settle non-conflicting transactions more quickly. Each transaction locks only the part of the state it touches, similar to a row-level lock in a traditional DBMS. In a nutshell, two (or more) transactions whose mutual order has not yet been decided can all be applied if they commute, i.e., their effect on the system's state is independent of the order in which they end up being confirmed. For applications that need ordering, pod allows custom ordering (sequencing) gadgets to be built on top that inherit the security of pod. This enables ordering-sensitive applications to decide on how they handle their application’s MEV while still maintaining fast composability with the base layer. pod supports EVMx, a backward-compatible extension of EVM. EVMx is designed to minimize the uplift of application developers required to leverage the fast path of pod. More on this is coming out soon.

Extensions
pod has a radically simple core (see above). pod employs several extensions on top that use cryptographic schemes or techniques from traditional databases to allow for additional features and optimizations. These extensions are designed in a trust-minimized fashion such that the security of the pod network relies only on the security of pod-core. Here are some such extensions:

Secondaries. We separate the computers that handle the write instructions and those that handle the read instructions. Secondaries are untrusted, read-only nodes that offload the burden of serving frequent read requests from validators, which handle only write instructions. Each validator signs and forwards new transactions to its secondaries, who cache these signed updates and forward them to the relevant subscribed nodes without overloading the validator. Because secondaries do not sign responses, they require no additional trust; the only harm they can do is stop responding, in which case a user simply switches to another secondary for the same validator.


Figure 3 (secondaries of a validator): Read operations are much more common than write operations in a blockchain system. More secondaries can be added to a validator to scale the read operations as much as needed.
‍

Gateways. Even though we have sharded the read instructions (i.e., not every read instruction hits every validator), having each client connect to all validators for write purposes is uneconomical. Instead, we operate helpful but untrusted gateways. A gateway is a node that maintains an open connection to all validators. Whenever a client wishes to write a transaction, all it needs to do is reach out to a gateway and send the relevant write instruction. The gateway then forwards this write to all validators, receives their signatures, assembles a confirmation certificate consisting of α signatures, and forwards this back to the client. If the client is unsatisfied from the performance of a gateway, he can switch to a different one. Like secondaries, gateways do not sign their responses, and therefore do not need to be trusted.


Figure 4 (the gateway architecture): Clients can avoid connecting to all validators by using a gateway, which maintains open connections to the current validator set.
‍

Thin validators. To further improve the network's decentralization, we can reduce the storage needed by the active validators by not requiring them to store past logs. This can be done by using Merkle Mountain Ranges (MMR), where each leaf of the tree is a pair of transactions and its corresponding timestamp. Instead of storing the complete historical log, the validators are now only required to maintain the latest peaks of the MMR. Whenever a validator wishes to add a new transaction to the log, it updates this MMR accordingly and sends its corresponding secondaries attested root together with the timestamp.


Figure 5 (a validator’s MMR): The validator only maintains the right-most slope of the MMR of logarithmic size. Whenever a new transaction arrives, the slope is sufficient to calculate the new MMR slope and its root.
‍

Light clients. pod has built-in light client support based on an elegant and simple, yet efficient, data structure called a Merkle Segment Mountain Range that uses bloom filters. The structure combines Merkle Trees with Segment Trees to allow for accountable light clients. Light clients can not only verifiably obtain information about the smart contracts they’re interested in but can also verify, in an accountable fashion, that no information has been omitted. The construction does not require the light client to trust any server intermediaries. Our light client data structure borrows and extends older, well-understood protocols such as Google’s Certificate Transparency.

Security Analysis
This is a high-level overview of pod-core's security analysis. For the complete analysis and findings, please refer to the pod-core paper.

The security analysis of pod-core rests on two critical parameters: the quorum size α corresponding to liveness resilience n - α, and the safety resilience β. Classical quorum-based consensus systems set n - α = β = 1/3. In pod, these parameters are configurable.

When a client observes a transaction signed by γ ≥ α of the validators (a certificate), the median of the timestamps signed by those validators for that transaction is taken as the confirmed timestamp. The minimum and maximum timestamp assurances for a given transaction can be computed as follows. Initially, all the timestamps associated with a transaction by validators are collected and sorted. Those validators who have not yet included the transaction in their log are counted as having included it with the timestamp of their last good response (if a validator has never responded, their last good response has a timestamp of 0). The highest β of these timestamps are set to their worst-case value of 0, and the median among the lowest α is taken as the pessimistic minimum. For calculating the pessimistic maximum, the timestamps are similarly collected and sorted, the lowest β of these are set to their worst-case value of positive infinity, and the median among the highest α is taken as the pessimistic maximum. Naturally, if fewer than α signatures (conditioned on α > 2β) have been received about a transaction, its minimum is set to 0, and its maximum is set to positive infinity, for now.

Additionally, a client maintains a perfect timestamp. For any transaction yet to be observed, its confirmed timestamp is guaranteed to be greater than the client's perfect timestamp. This essentially ensures that no new transaction can be confirmed with a past timestamp. This perfect timestamp is calculated by collecting the timestamp of the last good response by each of the validators, sorting these timestamps, setting the highest β of these to 0, and taking the median of the lowest α.

More formally, pod provides the following guarantees. In the following, α is the quorum size, n - α is the liveness resilience, β is the safety resilience, Δ is the upper bound on the network delay after GST, and δ is the actual network delay.

Accountable Liveness: As long as the adversary controls fewer than n - α validators, in partial synchrony, after GST, any honest transaction is confirmed within 2δ, and with a confirmation timestamp within δ, from the moment the honest transaction is sent to the network. Additionally, in asynchrony, transactions are eventually confirmed. Furthermore, after GST, an adversary who controls fewer than min(α, n - α) validators can be held accountable for not confirming transactions within Δ. Moreover, after GST, if f < α/2, a transaction’s temperature max - min in the view of all honest parties will be at most δ for all transactions, regardless of whether they are honest or adversarial.
Accountable Safety: As long as the adversary controls fewer than β validators, if a transaction is marked as confirmed with confirmed timestamp t1​ by one honest party, then this confirmed timestamp will fall between the min and max reported by every honest party earlier or later. Additionally, any transaction that was not seen by an honest party by a particular point in time will never appear confirmed with a timestamp prior to the perfect timestamp reported by that party at that point in time. In case either of these properties fails, at least β adversarial-only validators can be held accountable.
Gratitude and credits for past work
This work wouldn’t be possible without decades of amazing work done by scientists and engineers in the blockchain space. We especially want to thank the Ethereum community, Mysten Labs (SUI), and Flashbots. Check out the pod-core paper for related works and a complete list of references.
Coming from Ethereum?
Those familiar with the Ethereum ecosystem will recognize the EVM environment and similar RPC interface, but pod rethinks core assumptions around execution and ordering.

Execution Model
pod does not have a globally ordered chain of blocks, and therefore does not maintain a single, globally agreed-upon state mapping. Each validator executes transactions according to its local view, which may differ in order or timing from other nodes.

However, for order-independent applications—where the outcome is unaffected by the relative ordering of unrelated transactions—the resulting state across honest validators will converge in all observable outputs once they have seen the same set of transactions. This includes things like logs emitted, token balances, and receipt contents.

Even if internal storage layouts or execution traces differ, these applications will see consistent results from their point of view. In contrast, applications that rely on strict ordering must sequence transactions before sending them to pod.

Solidity and EVM
pod supports EVM (specifically the Prague version), but with important caveats:

block.timestamp is the local validator’s time, not a globally agreed timestamp.
block.number, block.coinbase, block.difficulty, and block.basefee are all set to 0.
Smart contracts must be written to tolerate the absence of global context and ordering.
Any time-sensitive logic must treat timestamps as advisory and potentially inconsistent.
JSON-RPC
pod supports most of the Ethereum JSON-RPC interface, but with critical deviations:

All standard Ethereum RPCs are supported, however Block-related queries like eth_getBlockByNumber or eth_getBlockByHash respond with empty block data and should not be used in application logic.
Special Metadata Field: pod_metadata
All RPC responses include a special JSON field called pod_metadata. This field contains pod-specific metadata useful for validation and auditing.

For transaction receipts, pod_metadata includes a list of attestations (signatures from validators). If the number of attestations is greater than two-thirds of the current validator set, the receipt is considered confirmed. This replaces traditional “confirmation count” logic in block-based chains.

Applications should use these attestations to verify transaction finality instead of relying on block numbers or confirmation depths.

pod-specific extensions:
pod_getCommittee: Returns the current validator set.
pod_listAccountReceipts: Returns receipts involving a given account as sender or receiver.
pod_listConfirmedReceipts: Returns receipts confirmed between two timestamps, as observed by the connected full node. Since time is not globally agreed, this is a local view.


Pod network
Tokens
Creating a fungible token
Unlike traditional blockchains where token logic runs over globally ordered blocks, pod allows token contracts to enforce safety (e.g. no overdrafts) even when transactions are confirmed independently and concurrently.

This guide shows how to create and use a simple fungible token using FastTypes.Balance, a type provided by pod-sdk that integrates directly with pod’s validator quorum logic.

To get started, clone podnetwork/pod-sdk github repository and go to examples/tokens directory:


$ git clone github.com/podnetwork/pod-sdk && cd examples/tokens
Smart Contract Definition
As in the ERC20 Token Standard, each Token contract instance corresponds to a single fungible token, defined by its own name, ticker symbol, number of decimals, and fixed total supply.

The contract makes use of the FastTypes library provided by pod-sdk.

The FastTypes.Balances type provides

_balances.decrement(key, owner, value), a method that allows only the owner himself to decrease his balance,
_balances.increment(key, owner, value), that allows anyone to increase the balance of an owner
Unlike a plain Solidity mapping, when you call decrement method of a FastTypes.Balance, you’re enforcing that a supermajority of validators agree the account has sufficient funds, up to the previous transaction by this account. That makes balance checks consistent across the network even without full consensus.

The key parameter is a string that allows namespacing for multiple balances by the same owner, but in this example we always use the variable symbol as the key, as there is only a single balance for each address.

Token.sol

pragma solidity ^0.8.26;

import {FastTypes} from "pod-sdk/FastTypes.sol";

contract Token {
    using FastTypes for FastTypes.Balance;

    uint256 public totalSupply;
    uint8 public decimals;
    string  public name;
    string  public symbol;

    // This is a special type that is safe in the fast path of pod.
    // Checkout more about the type at https://docs.v1.pod.network/smart-contract-development/solidity-sdk-reference#balance
    FastTypes.Balance internal _balances;

    event Transfer(address indexed from, address indexed to, int256 value);

    constructor(
        string  memory tokenName,
        string  memory tokenSymbol,
        uint8 decimals,
        uint256 initialSupply
    ) {
        name = tokenName;
        symbol = tokenSymbol;
        decimals = decimals;
        totalSupply = initialSupply;
        _balances.increment(symbol, msg.sender, totalSupply);
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        // The decrement function ensures that the sender has enough balance
        _balances.decrement(symbol, msg.sender, amount);
        _balances.increment(symbol, to, amount);
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}
Deployment
Deploying with forge

$ forge create --rpc-url https://rpc.v1.dev.pod.network \
    --private-key $PRIVATE_KEY \
    contracts/Tokens.sol:Tokens \
    --broadcast \
    --constructor-args "token" "TKC" 9 1000000000000
Transfer token programmatically
This example demonstrates how to transfer tokens programmatically.

Token transfer

use pod_sdk::{PodProvider, Wallet};
use alloy_sol::sol;
use alloy_core::types::*;
use alloy_primitives::B256;
use std::error::Error;

sol! {
    interface Token {
        function transfer(address to, uint256 amount) external;
    }
}

async fn transfer_tokens(pod_provider: &PodProvider, contract_address: Address, destination_address: Address, amount: U256) -> Result<(), Box<dyn Error>> {
    let contract = Token::new(contract_address, provider.clone());
    let call = contract.transfer(destination_address, amount).send().await?;
    let tx_hash = call.tx_hash();
    if let Some(receipt) = provider.get_transaction_receipt(*tx_hash).await? {
        println!("Tokens sent with receipt: {:?}", receipt);
    }
    Ok(())
}
Transfer events
Transfer events are emitted on every token transfer.

Clients can request verifiable logs from the RPC full nodes. These proofs can be verified locally if the RPC node is not trusted, or submitted to light clients, ie smart contracts in other blockchains that verify that an event was emitted in pod.

Token events

use pod_sdk::{PodProvider, Committee};
use alloy_core::types::*;
use alloy_core::log::Filter;
use std::error::Error;

sol! {
    interface Token {
        event Transfer(address indexed from, address indexed to, uint256 value);
    }
}

async fn event_transfer(pod_provider: &PodProvider, committee: &Committee, destination_address: Address, rpc_is_trusted: bool) -> Result<(), Box<dyn Error>> {
    // Filter transfer by specifying a destination address
    let filter = Filter::new().event_signature(Transfer::SIGNATURE).topic1(destination_address);
    let logs = pod_provider.get_verifiable_logs(&filter).await?;
    for log in logs {
        if rpc_is_trusted || log.verify(committee)? {
            println!("Verified transfer at {:?}: {:?}", log.confirmation_time(), log);
        }
    }
    Ok(())
}
untitled page




Solidity SDK Reference
The Solidity SDK is available at the pod-sdk github repository.

For example, to install with forge use:


 $ forge install podnetwork/pod-sdk
Fast types
The FastTypes library provides coordination-free data structures through precompiled contracts. All operations are designed to be commutative and safe under pod’s consensus model which avoids coordination between the validators.

A smart contract written for pod must not depend on the order of transactions arriving to a validator, otherwise there may be inconsistencies between validators, which may lead to safety issues or a correct transaction to not be approved. However, if a smart contract is written to use only types from FastTypes as storage, then it is guaranteed to be safe despite lack of coordination.

To use the library, import the necessary types from pod-sdk/FastTypes.sol:


import {SharedCounter} from "pod-sdk/FastTypes.sol";
OwnedCounter
A collection of owned uint256 values. It can be considered as one bytes32 => uint256 mapping for each transaction sender. Functions revert if a sender is trying to manipulate the value owned by another address.

Functions

set(address owner, bytes32 key, uint256 value): Set counter to value. Ignores previous values.
increment(address owner, bytes32 key, uint256 value): Increment counter owned by owner, by value.
decrement(address owner, bytes32 key, uint256 value): Decrement counter owned by owner by value.
get(address owner, bytes32 key): Retrieve value of counter.
All functions revert if tx.origin does not equal owner. The key allows for every owner to have multiple values. The same key on different owners refers to different values.

Why is OwnedCounter coordination-free? If two transactions were sent by different users then they cannot access the same key, and if they were sent by the same user they are already ordered by the account nonce.

SharedCounter
Shared monotonically increasing values that support increment and threshold checking operations.

Functions

increment(bytes32 key, uint256 value): Increase counter named key by value.
requireGte(bytes32 key, uint256 value, string errorMessage): Revert if counter named key is less than value.
Why is SharedCounter coordination-free? While the SharedCounter allows transactions by different users to affect the same memory, it does not matter in which order the increments happen: if reguireGte is true for one validator it will remain true forever and will eventually be true for all other validators as well. Importantly, the shared counter does not allow decreasing the counter, or checking if it is smaller than some value (eg. reguireLte), because both would violate this principle.

Balance
A collection of uint256 values, where every sender can decrement (spend) his value, but anyone can increment (debit) anyone else’s value. This is a basic building block for building any kind of token balances. It does not enforce that incrementing value of one address must decrement some amount from another address.

Functions

increment(address owner, bytes32 key, uint256 value) Increase the balance of owner for key by value. Anyone can call.
decrement(address owner, bytes32 key, uint256 value) Decrease balance of owner for key by value. Only owner can call.
requireGte(address owner, bytes32 key, string errorMessage) Require that the balance of owner for key is at least value. Only owner can call.
See Tokens or NFTs for examples using the Balance type.

Why is Balance coordination-free? It is essentially a combination of SharedCounter and OwnedCounter.

Uint256Set
Shared collection of uint256 values.

Functions

add(uint256 value) Add a value to the set.
requireExists(uint256 value, string error) Revert if value not in the set.
requireLengthGte(uint256 length, string error) Revert if size of set less than length.
requireMaxValueGte(uint256 value, string error) Revert if maximum value in set less than value.
Why is Uint256Set coordination-free? A set with add and exists operations is the most typical CRDT operation. It does not matter in which order elements are added to a set. However, removing elements is non-monotonic and requires coordination. Instead, deletion can be implemented by having a second set, the set of all deleted values.

AddressSet
Shared collection of addresses.

Functions

add(address addr) Add address to the set.
requireExists(address addr, string error) Revert if address is not in the set.
requireLengthGte(uint256 length, string error) Revert if set does not contain at least length addresses.
Time
The Time package provides utilities for working with time on pod. These utilities work by accessing the local time on each validator, which depends on the time that they first see a transaction.

They ensure that a supermajority of the validators agree on a statement (for example, that the transaction was sent before (or after) a certain time. They also ensure that even if some small minority of validators did not see the transaction in time but later (for example, due to connectivity issues), they will still accept the transaction and execute the same code as the supermajority.

To use, import requireTimeAfter or requireTimeBefore from pod-sdk/Time.sol:


import {requireTimeAfter, requireTimeBefore} from "pod-sdk/Time.sol";
requireTimeBefore

function requireTimeBefore(uint256 timestamp, string memory message) view
Requires that the current timestamp is before the specified time.

Parameters:

timestamp: Unix timestamp that must be in the future
message: Error message if validation fails
Behavior:

Validates that the current timestamp is less than the specified timestamp
Uses validators’ local timestamps - each validator has a different local time
Ensures a supermajority of validators saw the transaction before the required time
Reverts with the provided message if condition fails
Accounts for validator clock differences across the network
See Auctions for an example that uses requireTimeBefore.

requireTimeAfter

function requireTimeAfter(uint256 timestamp, string memory message) view
Requires that the current timestamp is after the specified time.

Parameters:

timestamp: Unix timestamp that must be in the past
message: Error message if validation fails
Behavior:

Validates that the current timestamp is greater than the specified timestamp
Uses validators’ local timestamps - each validator has a different local time
Ensures a supermajority of validators saw the transaction after the required time
Reverts with the provided message if condition fails
Accounts for validator clock differences across the network
untitled page




Pod network
RPC API
This documentation provides detailed information about the JSON-RPC methods supported by pod.

Overview
Pod implements a JSON-RPC API that allows interaction with the network. While many methods align with the Ethereum JSON-RPC specification (methods prefixed with eth_), pod includes additional metadata (pod_metadata attribute) and pod-specific functionality (methods prefixed with pod_).

Base URL
The API endpoint is accessible at https://rpc.v1.dev.pod.network.

API endpoint

https://rpc.v1.dev.pod.network
Common Response Fields
All successful responses include:

Field	Description
jsonrpc	Always “2.0”
id	The request ID
result	The method-specific response data
pod_metadata	Additional POD-specific information (location varies by method)
Parameters must match the JSON-RPC 2.0 specification.

Parameters

{
	"jsonrpc": "2.0",
	"method": "method_name",
	"params": [],
	"id": 1
}
Error Handling
Error responses follow the JSON-RPC 2.0 specification.

Error Codes
Code	
32700	Parse error
32600	Invalid Request
32601	Method not found
32602	Invalid params
32603	Internal error
32000	Server error (various)
Error responses follow the JSON-RPC 2.0 specification:

Error Response

{
	"jsonrpc": "2.0",
	"error": {
		"code": -32000,
		"message": "Error message"
	},
	"id": 1
}
Get Block Number
Returns the latest past perfection pod timestamp in microseconds.

Parameters
None

Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	string	latest block number
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let block_number = pod_provider.get_block_number().await?;
    println!("{}", block_number);

    Ok(())
}
curl -L \
  --request POST \
  --url 'https://rpc.v1.dev.pod.network/' \
  --header 'Content-Type: application/json' \
  --data '{
    "jsonrpc": "2.0",
    "method": "eth_blockNumber",
    "params": [],
    "id": 1
  }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_blockNumber',
		params: [],
		id: 1
	})
});
Example Response:


{
	"jsonrpc": "2.0",
	"result": "0x67505ef7",
	"id": 1
}
Get Chain Id
Returns the chain ID of the current network.

Parameters
None

Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	string	Chain ID in hexadecimal format, always 0x50d
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let chain_id = pod_provider.get_chain_id().await?;
    println!("{}", chain_id);

    Ok(())
}
curl -L \
  --request POST \
  --url 'https://rpc.v1.dev.pod.network/' \
  --header 'Content-Type: application/json' \
  --data '{
    "jsonrpc": "2.0",
    "method": "eth_chainId",
    "params": [],
    "id": 1
  }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_chainId',
		params: [],
		id: 1
	})
});
Example Response:


{
    "jsonrpc": "2.0",
    "id": 1,
    "result": "0x50d"
}



Get Gas Estimation
Estimates gas needed for a transaction.

Parameters
Parameter	Type	Description
object	object	Transaction call object with the following fields:
from	string	(optional) 20-byte address of sender
to	string	20-byte address of recipient
gas	string	(optional) Gas provided for transaction execution
gasPrice	string	(optional) Gas price in wei
value	string	(optional) Value in wei
data	string	(optional) Contract code or encoded function call data
Note: Only Legacy transactions are supported

Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	string	estimated gas in hexadecimal format
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let recipient_address = Address::from_word(b256!("0x000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045"));
    let transfer_amount = U256::from(1_000_000); // 1 million wei

    let tx = PodTransactionRequest::default()
            .with_to(recipient_address)
            .with_value(transfer_amount);

    let gas_estimation = pod_provider.estimate_gas(&tx).await?;
    println!("{}", gas_estimation);

    Ok(())
}
curl -X POST https://rpc.v1.dev.pod.network \
    -H "Content-Type: application/json" \
    -d '{
        "jsonrpc": "2.0",
        "method": "eth_estimateGas",
        "params": [{
            "from": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
            "to": "0xbe0eb53f46cd790cd13851d5eff43d12404d33e8"
        }],
        "id": 1
    }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_estimateGas',
		params: [
			{
				from: '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
				to: '0xbe0eb53f46cd790cd13851d5eff43d12404d33e8'
			}
		],
		id: 1
	})
});
Example Response:


{
    "jsonrpc": "2.0",
    "result": "0x493e0",
    "id": 1
}
Get Gas Price
Returns the current gas price.

Parameters
None

Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	string	Current gas price in wei (hexadecimal format)
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let gas_price = pod_provider.get_gas_price().await?;
    println!("{}", gas_price);

    Ok(())
}
curl -X POST https://rpc.v1.dev.pod.network \
    -H "Content-Type: application/json" \
    -d '{
        "jsonrpc": "2.0",
        "method": "eth_gasPrice",
        "params": [],
        "id": 1
    }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_gasPrice',
		params: [],
		id: 1
	})
});
Example Response:


{
    "jsonrpc": "2.0",
    "result": "0x1",
    "id": 1
}

Get Balance
Returns the balance of a given address.

Parameters
Parameter	Type	Description
string 1	string	20-byte address to check balance for
string 2	string	Past perfect timestamp to query, specified in seconds(hexadecimal format). Can also be the tags: earliest, finalized or latest.
Note: Currently returns the current balance regardless of timestamp

Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	string	balance in hexadecimal format
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
rust
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let address = Address::from_word(b256!("0x000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045"));

    let balance = pod_provider.get_balance(address).await?;
    println!("{}", balance);

    Ok(())
}
curl -X POST https://rpc.v1.dev.pod.network \
    -H "Content-Type: application/json" \
    -d '{
        "jsonrpc": "2.0",
        "method": "eth_getBalance",
        "params": [
            "0x13791790Bef192d14712D627f13A55c4ABEe52a4",
            "0x1"
        ],
        "id": 1
    }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_getBalance',
		params: [
			'0x13791790Bef192d14712D627f13A55c4ABEe52a4',
			'0x1'
		],
		id: 1
	})
});
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let response = client
        .post("https://rpc.v1.dev.pod.network/")
        .header("Content-Type", "application/json")
        .json(&json!({
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [
                "0x13791790Bef192d14712D627f13A55c4ABEe52a4",
                "0x1"
            ],
            "id": 1
        }))
        .send()
        .await?;

    let result: Value = response.json().await?;
    println!("{}", result);

    Ok(())
}
Example Response:


{
    "jsonrpc": "2.0",
    "result": "0x0",
    "id": 1
}


Get Block by Hash
Returns information about a block by its hash. Returns an empty block structure for compatibility.

Parameters
Parameter	Type	Description
element 1	string	Block hash
element 2	boolean	If true, returns full transaction objects; if false, returns transaction hashes
Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	object	block information
Key	Type	Description
result	object	block information
result.number	string	0
result.mixHash	string	0x0 followed by 64 zeros
result.hash	string	Requested block hash
result.parentHash	string	0x0 followed by 64 zeros
result.nonce	string	0x0000000000000000
result.sha3Uncles	string	0x0 followed by 64 zeros
result.logsBloom	string	0x0 followed by 256 zeros
result.transactionsRoot	string	0x0 followed by 64 zeros
result.stateRoot	string	0x0 followed by 64 zeros
result.receiptsRoot	string	0x0 followed by 64 zeros
result.miner	string	0x0 followed by 40 zeros
result.difficulty	string	0x0000000000000000
result.extraData	string	0x0 followed by 40 zeros
result.size	string	0x0
result.gasLimit	string	0x0
result.gasUsed	string	0x0
result.timestamp	string	0x0
result.transactions	array	Empty array
result.uncles	array	Empty array
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let block = pod_provider
            .get_block_by_hash(
                b256!("0x000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045"),
                BlockTransactionsKind::Full,
            )
            .await?;
    println!("{}", block);

    Ok(())
}
curl -X POST https://rpc.v1.dev.pod.network \
    -H "Content-Type: application/json" \
    -d '{
        "jsonrpc": "2.0",
        "method": "eth_getBlockByHash",
        "params": [
            "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            false
        ],
        "id": 1
    }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_getBlockByHash',
		params: ['0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef', false],
		id: 1
	})
});
Example Response:


{
	"jsonrpc": "2.0",
	"result": {},
	"id": 1
}


Get Block by Number
Returns information about a block by its number. Returns an empty block structure for compatibility.

Parameters
Parameter	Type	Description
element 1	string	Block number in hexadecimal format
element 2	boolean	If true, returns full transaction objects; if false, returns transaction hashes
Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	object	block information
Key	Type	Description
result	object	block information
result.number	string	Requested block number
result.mixHash	string	0x0 followed by 64 zeros
result.hash	string	0x0 followed by 64 zeros
result.parentHash	string	0x0 followed by 64 zeros
result.nonce	string	0x0000000000000000
result.sha3Uncles	string	0x0 followed by 64 zeros
result.logsBloom	string	0x0 followed by 256 zeros
result.transactionsRoot	string	0x0 followed by 64 zeros
result.stateRoot	string	0x0 followed by 64 zeros
result.receiptsRoot	string	0x0 followed by 64 zeros
result.miner	string	0x0 followed by 40 zeros
result.difficulty	string	0x0000000000000000
result.extraData	string	0x0 followed by 40 zeros
result.size	string	0x0
result.gasLimit	string	0x0
result.gasUsed	string	0x0
result.timestamp	string	0x0
result.transactions	array	Empty array
result.uncles	array	Empty array
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let block = pod_provider
        .get_block_by_number(
            BlockNumberOrTag::Number(1),
            BlockTransactionsKind::Full,
        )
        .await?;
    println!("{}", block);

    Ok(())
}
curl -X POST https://rpc.v1.dev.pod.network \
    -H "Content-Type: application/json" \
    -d '{
        "jsonrpc": "2.0",
        "method": "eth_getBlockByNumber",
        "params": [
            "0x1",
            false
        ],
        "id": 1
    }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_getBlockByNumber',
		params: ['0x1', false],
		id: 1
	})
});
Example Response:


{
	"jsonrpc": "2.0",
	"result": {},
	"id": 1
}

Get Logs
Returns an array of event logs matching the given filter criteria.

Parameters
Parameter	Type	Description
fromBlock	string	(optional) From block timestamp specified in seconds in hexadecimal format. Can also be the tags: earliest, finalized or latest.
toBlock	string	(optional) To block timestamp specified in seconds in hexadecimal format. Can also be the tags: earliest, finalized or latest.
address	string	(optional) Contract address
topics	array	(optional) Array of topic filters (up to 4 topics):
- Each topic can be either a string or null
- Topics are ordered and must match in sequence
- Null values match any topic
minimum_attestations	number	(optional) Minimum number of attestations required for the log to be returned
Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	array	Array of log objects
Key	Type	Description
object	block information
address	string	Address from which this log originated
blockNumber	string	Block number in hexadecimal format, supported for completeness, the block number returned is 1
blockHash	string	Block hash. Supported for completeness, the block hash returned is the 0 hash
transactionHash	string	Transaction hash
transactionIndex	string	Transaction index
logIndex	string	Log index
topics	array	Array of indexed log parameters
data	string	Contains non-indexed log parameters
pod_metadata	object	Additional pod-specific information including attestations
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let topic = U256::from_str(
            &"0x71a5674c44b823bc0df08201dfeb2e8bdf698cd684fd2bbaa79adcf2c99fc186".to_string(),
        )?;

    let filter = Filter::new()
        .address(Address::from_str(
            "0x1234567890123456789012345678901234567890",
        )?)
        .topic2(topic);

    let verifiable_logs = pod_provider.get_verifiable_logs(&filter).await?;
    println!("{:?}", verifiable_logs);

    for v_log in &verifiable_logs {
        let is_valid = v_log.verify(&committee)?;
        println!("{:?}", is_valid);
    }

    Ok(())
}
curl -X POST https://rpc.v1.dev.pod.network \
    -H "Content-Type: application/json" \
    -d '{
        "jsonrpc": "2.0",
        "method": "eth_getLogs",
        "params": [{
            "address": "0x1234567890123456789012345678901234567890",
            "topics": [
                "0x71a5674c44b823bc0df08201dfeb2e8bdf698cd684fd2bbaa79adcf2c99fc186"
            ],
            "fromBlock": "0x1",
            "toBlock": "latest"
        }],
        "id": 1
    }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_getLogs',
		params: [
			{
				address: '0x1234567890123456789012345678901234567890',
				topics: ['0x71a5674c44b823bc0df08201dfeb2e8bdf698cd684fd2bbaa79adcf2c99fc186'],
				fromBlock: '0x1',
				toBlock: 'latest'
			}
		],
		id: 1
	})
});
Example Response:


{
	"jsonrpc": "2.0",
	"result": [],
	"id": 1
}

List Confirmed Receipts
Retrieves confirmed transaction receipts after a specified timestamp. Allows filtering receipts by originating or destination address.

Parameters
Key	Type	Description
object	
since	string	Timestamp specified in microseconds representing the start of the range to query
address	string	(optional) Address to filter receipts by (matches from or to fields)
pagination	object	(optional) Pagination object
pagination.cursor	string	(optional) Cursor to start the query from
pagination.limit	integer	(optional) Maximum number of receipts to return
pagination.newest_first	boolean	(optional) Whether to start the query from the most recent receipts
Note: If cursor is provided, newest_first must NOT be provided.

Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	object	Response object
Key	Type	Description
object	Pagination Response Object
items	array	List of transaction receipts with metadata
next_cursor	string	Cursor to start the next query from. null if there are no more items to fetch
POST rpc.v1.dev.pod.network
 
curl
javascript
rust
curl -X POST https://rpc.v1.dev.pod.network \
    -H "Content-Type: application/json" \
    -d '{
        "jsonrpc": "2.0",
        "method": "pod_listReceipts",
        "params": {
            "since": 0
        },
        "id": 1
    }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'pod_listReceipts',
		params: {
			since: 0
		},
		id: 1
	})
});
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::new();
    let response = client
        .post("https://rpc.v1.dev.pod.network/")
        .header("Content-Type", "application/json")
        .json(&json!({
            "jsonrpc": "2.0",
            "method": "pod_listReceipts",
            "params": {
                "since": 0
            },
            "id": 1
        }))
        .send()
        .await?;

    let result: Value = response.json().await?;
    println!("{}", result);

    Ok(())
}
Example Response

{
	"jsonrpc": "2.0",
	"id": 1,
	"result": {
		"items": [
			{
				"blockHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
				"blockNumber": "0x1",
				"contractAddress": null,
				"cumulativeGasUsed": "0x5208",
				"effectiveGasPrice": "0x3b9aca00",
				"from": "0xb8aa43999c2b3cbb10fbe2092432f98d8f35dcd7",
				"gasUsed": "0x5208",
				"logs": [],
				"logsBloom": "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
				"pod_metadata": {
					"attestations": [
						{
							"public_key": "0x7d5761b7b49fc7bfdd499e3ae908a4acfe0807e6",
							"signature": {
								"r": "0x30262c9f183a9f7219d260affbf6c8f92bff24a094d63ff9ed3c7366076f7bd7",
								"s": "0x6a6ff240bbab35626d6f4ea2a27a2d9d739f9305a5f1bcabe0eaf1e14364390a",
								"v": "0x0",
								"yParity": "0x0"
							},
							"timestamp": 1740419698722233
						},
						{
							"public_key": "0xd64c0a2a1bae8390f4b79076ceae7b377b5761a3",
							"signature": {
								"r": "0x45a87fdf1455b5f93660c5e265767325afbd1e0cfa327970a63e188290625f9d",
								"s": "0x65343279465e0f1e43729b669589c2c80d12e95a72a5a52c63b70b3abf1ebef5",
								"v": "0x1",
								"yParity": "0x1"
							},
							"timestamp": 1740419698722014
						},
						{
							"public_key": "0x06ad294f74dc98be290e03797e745cf0d9c03da2",
							"signature": {
								"r": "0xf9d7f79e339b68f75eb6d172dc68539a1d0750c555979f998cb8a9211fdc1511",
								"s": "0x7239b2efc00415dd5866bf564366272af8fb4738c7697fec50628b9969521493",
								"v": "0x1",
								"yParity": "0x1"
							},
							"timestamp": 1740419698721922
						},
						{
							"public_key": "0x8646d958225301a00a6cb7b6609fa23bab87da7c",
							"signature": {
								"r": "0x8c8256bea8c0e919618abd973646d344e8ffe3c50c0757ce902d28659f1524b4",
								"s": "0x3b76b3818666a418572cc465d30638533d4bd987bfb5dd0550a311521f167719",
								"v": "0x1",
								"yParity": "0x1"
							},
							"timestamp": 1740419698722052
						}
					]
				},
				"status": "0x1",
				"to": "0x13791790bef192d14712d627f13a55c4abee52a4",
				"transactionHash": "0xfa71ee80b1bc58e00f4fe11ae1de362201de43ff65e849dcb5d8b92e0be71e87",
				"transactionIndex": "0x0",
				"type": "0x0"
			}
		],
		"next_cursor": "Y3I6MDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAxNzQwNDE5Njk3MjQ3NTczXzB4NzRjOWM0MTFkZDJjMDg0ZWE4NmZjOThjMDUwYWU0OTI4YTgzZjVlN2I3N2UyN2NkYTA5NWFiYmY0YTk1ZjJmY3xjcjowMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDBfMHgwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAw"
	}
}


Get Transaction Receipt
Returns the receipt of a transaction by transaction hash.

Parameters
Parameter	Type	Description
string 1	string	32-byte transaction hash
Response
Key	Type	Description
statusCode	integer	HTTP status code
response.jsonrpc	string	same value as request
response.id	integer	unique value as request
response.result	object	A transaction receipt object with pod-specific metadata, or null if no receipt was found.
Key	Type	Description
object	Standard Ethereum receipt fields
pod_metadata	object	Contains pod-specific data including attestations
POST rpc.v1.dev.pod.network
 
rust
curl
javascript
use reqwest::Client;
use serde_json::{json, Value};

async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let tx_receipt = pod_provider
        .get_transaction_receipt(
            b256!("0xf74e07ff80dc54c7e894396954326fe13f07d176746a6a29d0ea34922b856402"),
        )
        .await?;
    println!("{:?}", tx_receipt);

    let committee = pod_provider.get_committee().await?;

    let verification = tx_receipt.verify(&committee)?;
    println!("{:?}", verification);

    Ok(())
}
curl -X POST https://rpc.v1.dev.pod.network \
    -H "Content-Type: application/json" \
    -d '{
        "jsonrpc": "2.0",
        "method": "eth_getTransactionReceipt",
        "params": [
            "0xf74e07ff80dc54c7e894396954326fe13f07d176746a6a29d0ea34922b856402"
        ],
        "id": 1
    }'
await fetch('https://rpc.v1.dev.pod.network/', {
	method: 'POST',
	headers: {
		'Content-Type': 'application/json'
	},
	body: JSON.stringify({
		jsonrpc: '2.0',
		method: 'eth_getTransactionReceipt',
		params: [
			'0xf74e07ff80dc54c7e894396954326fe13f07d176746a6a29d0ea34922b856402'
		],
		id: 1
	})
});
Example Response:


{
	"jsonrpc": "2.0",
	"result": {},
	"id": 1
}

