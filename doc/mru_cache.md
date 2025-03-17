# MRU Cache

## 1. Introduction

MRU (Most Recently Used) Cache is a cache eviction algorithm that prioritizes removing the most recently accessed data. When the cache reaches its capacity, the most recently accessed entry is evicted, and the least recently accessed entries are retained.

## 2. MRU Cache Mechanism

### 2.1 Basic Concepts

MRU Cache consists of the following elements:

- **Key**: A unique identifier for the data in the cache.
- **Value**: The actual data stored in the cache.
- **Order**: A record of the data access order. The most recently used data is moved to the end of the list.

### 2.2 Eviction Policy

The eviction policy of MRU Cache follows these rules:

1. **Eviction of the Most Recently Used Data**
   - When the cache is full, the most recently accessed entry is evicted.

## 3. Workflow

### 3.1 Retrieving Data (`get` operation)

1. If the key exists:
   - Return the value.
   - Update the order and move the accessed data to the end of the list.
2. If the key does not exist:
   - Return `null`.

### 3.2 Inserting Data (`set` operation)

1. If the key exists:
   - Update the value.
   - Update the order and move the accessed data to the end of the list.
2. If the key does not exist:
   - If the cache exceeds the [maxSize], evict the most recently accessed entry based on the MRU policy.
   - Add the new key-value pair.

### 3.3 Example: MRUCache Operations and State Changes

1. Initial State: MRUCache<maxCount: 3>

   - The cache is empty.
     | Order | Key |
     | ----- | --- |
     | 0 | - |

2. set A

   - Add key A to the cache. The order is 1 for the first entry.
     | Order | Key |
     | ----- | --- |
     | 1 | A |

3. set B

   - Add key B. The order updates, and B becomes the newest entry.
     | Order | Key |
     | ----- | --- |
     | 1 | A |
     | 2 | B |

4. get A

   - Retrieve key A. The order is updated, and A moves to the end of the list.
     | Order | Key |
     | ----- | --- |
     | 2 | B |
     | 3 | A |

5. set C

   - Add key C. The new entry is added to the cache.
     | Order | Key |
     | ----- | --- |
     | 2 | B |
     | 3 | A |
     | 4 | C |

6. set D (A evicted due to MRU)

   - Add key D. Since the cache has reached its max size (maxSize: 3), C, being the most recently accessed, is evicted.
     | Order | Key | Value |
     | ----- | --- | ----- |
     | 2 | B | ... |
     | 3 | A | ... |
     | 5 | D | ... |

## 4. Suitable Use Cases

MRU Cache is particularly effective when:

- **Locality of access is not expected**, or
- **The complexity of implementing LRU is too high**.

It is ideal in scenarios where recently accessed data is unlikely to be reused soon, allowing the MRU policy to quickly evict unnecessary data.

Examples:

- **Database Memory Cache**:  
  When caching query results or indexes, MRU is useful if the recently queried data is unlikely to be reused.
- **Streaming Processing**:  
  Ideal for maintaining only the latest data, where the most recent data is discarded immediately after being used.
