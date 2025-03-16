# LRU Cache

## 1. Introduction

LRU (Least Recently Used) Cache is a cache replacement algorithm that prioritizes deleting the least recently used data. When the cache is full, the least recently accessed data is removed, and the most recently accessed data is kept.

## 2. LRU Cache Mechanism

### 2.1 Basic Concepts

An LRU Cache consists of the following elements:

- **Key**: A value used to uniquely identify data within the cache.
- **Value**: The actual data stored in the cache.
- **Order**: Tracks the access order of data within the cache. The most recently used data is moved to the end of the list.

### 2.2 Eviction Policy

The eviction policy of an LRU Cache follows these rules:

1. **Evict the least recently used data**
   - When the cache reaches its capacity, the entry that was accessed the least recently is evicted.

## 3. Workflow

### 3.1 Data Retrieval (`get` operation)

1. If the key exists:
   - Return the value.
   - Update the order by moving the accessed data to the end of the list.
2. If the key does not exist:
   - Return `null`.

### 3.2 Data Insertion (`set` operation)

1. If the key exists:
   - Update the value.
   - Update the order by moving the accessed data to the end of the list.
2. If the key does not exist:
   - If the cache exceeds the [maxSize], evict the least recently accessed entry based on the LRU policy.
   - Add the new key-value pair.

### 3.3 Example: LRUCache Operations and State Changes

1. Initial State: LRUCache<maxCount: 3>

   - The cache is empty.
     | Order | Key |
     | ----- | --- |
     | 0 | - |

2. set A

   - Add key A to the cache. The initial addition is at order 1.
     | Order | Key |
     | ----- | --- |
     | 1 | A |

3. set B

   - Add key B. The new entry B is added later in the order.
     | Order | Key |
     | ----- | --- |
     | 1 | A |
     | 2 | B |

4. get A

   - Access key A. The order is updated, and A moves to the end of the list.
     | Order | Key |
     | ----- | --- |
     | 2 | B |
     | 3 | A |

5. set C

   - Add key C. A new entry is added.
     | Order | Key |
     | ----- | --- |
     | 2 | B |
     | 3 | A |
     | 4 | C |

6. set D (B evicted due to LRU)

   - Add a new key D. Since the cache has reached maxSize (3), B, being the least recently used, is evicted.
     | Order | Key | Value |
     | ----- | --- | ----- |
     | 2 | A | ... |
     | 4 | C | ... |
     | 5 | D | ... |

## 4. Suitable Use Cases

LRU Cache is particularly effective in the following use cases:

1. Prioritize recently accessed data

   - LRU Cache is highly effective for frequently accessed data, as it keeps the most recently accessed data and evicts the oldest.

   Examples:

   - **Local data cache**: Cache recently used data or computation results to speed up future access.
   - **API response cache**: Cache frequently accessed API responses within a short period to reduce server load.
