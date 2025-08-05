# IPC::Wrangler Project Summary

## Product Pitch

IPC::Wrangler lets you break up monolithic applications into
cooperating processes with minimal complexity. Clients make requests
to named providers and get responses - IPC::Wrangler handles
intelligent request routing, automatically deduplicates identical
in-flight requests, and caches responses to protect against thundering
herds. Built for non-blocking I/O from the ground up, so your
application stays responsive while coordinating distributed work.

## Core Concept

IPC::Wrangler provides a DBI-style abstraction for inter-process
communication with intelligent coordination features. It's designed as
a library that enables easy decomposition of monolithic applications
into distributed services with minimal complexity.

## Key Features

### Three Interaction Modes
- **Query**: Cacheable read operations that can be merged and deduplicated
- **Mutate**: Write operations that cannot be cached or merged
- **Subscribe**: Event streaming and pub/sub functionality

### Intelligent Request Management
- **Automatic deduplication** of identical in-flight requests
- **Response caching** with configurable TTL
- **Thundering herd protection** through cache-first lookup + pub/sub coordination
- **Non-blocking I/O** as a first-class concern

### Transport Abstraction
- **Plugin architecture** supporting multiple transport mechanisms
- **DBI-style connection strings** for transport configuration
- **Planned transports**: Unix domain sockets, TCP sockets, Redis, ZeroMQ

## Architecture

### Client-Provider Model
- **Servers** may be managed by IPC::Wrangler or external (like Redis)
- **Named providers** offer specific services on a server's bus
- **Clients** make requests using provider name, operation, and arguments
- **Configuration-driven** setup reduces boilerplate code

### Request Flow Pattern (Redis)
1. Client checks cache for existing response
2. If cache miss, client subscribes to response channel
3. Client publishes request to provider channel
4. Provider processes request (with deduplication for in-flight requests)
5. Provider writes response to cache, then publishes to response channel
6. Client receives response and unsubscribes

### Provider Concurrency Models
- **Threaded**: Multi-threaded request handling
- **Forked**: Process-per-request model
- **Event-loop**: Single-threaded async processing

## Technical Implementation

### Transport Layer
- **Initial focus**: Unix domain sockets (both SOCK_DGRAM and SOCK_STREAM)
- **Datagram advantages**: Natural message boundaries, stateless operation, simpler protocol
- **Stream advantages**: Unlimited message size, reliable delivery
- **Future**: TCP sockets for network transport, Redis for distributed coordination

### Message Protocol
- **Simple wire format**: Length-prefixed messages for streams, natural boundaries for datagrams
- **Request correlation**: Explicit request IDs for async operations
- **Message types**: Request, response, error, subscription data
- **Serialization**: Pluggable encode/decode interfaces

### Configuration
- **Shared configuration file** defining providers and transport mechanisms
- **Automatic module loading** based on transport requirements
- **DBI-style connection strings** for transport-specific parameters

## Competitive Positioning

IPC::Wrangler fills a gap in the Perl IPC ecosystem by providing:
- **Higher-level coordination** than basic IPC primitives
- **Caching and deduplication** not found in simple message buses
- **Transport abstraction** allowing evolution from simple to complex deployments
- **Localhost-first design** optimized for breaking up monoliths

In principle, the library could be ported to languages other than
Perl, creating cross-language IPC support.
