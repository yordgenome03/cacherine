# FIFO Cache

## 1. Introduction

FIFO (First In, First Out) Cache is a cache replacement algorithm that deletes the data that was first added to the cache. When the cache is full, the oldest data added is removed, and the later added data is retained.

## 2. FIFO Cache Mechanism

### 2.1 Basic Concepts

FIFO Cache consists of the following elements:

- **Key**: A value used to uniquely identify the data in the cache.
- **Value**: The actual data stored in the cache.
- **Order**: The order of data insertion into the cache. The first inserted data remains at the front of the list.

### 2.2 Eviction Policy

The FIFO Cache eviction policy follows these rules:

1. **Evict the first inserted data**
   - When the cache is full, the first inserted entry will be evicted.

## 3. Flow of Operations

### 3.1 Data Retrieval (`get` operation)

1. If the key exists:
   - Return the value.
   - The order is not changed.
2. If the key does not exist:
   - Return `null`.

### 3.2 Data Insertion (`set` operation)

1. If the key exists:
   - Update the value.
   - The order is not changed.
2. If the key does not exist:
   - If the cache exceeds the [maxSize], evict the first inserted entry based on FIFO policy.
   - Add the new key-value pair.

### 3.3 Example: FIFO Cache Operations and State Changes

1. Initial State: FIFOCache<maxCount: 3>

   - The cache is empty.
     | Order | Key |
     | ----- | --- |
     | 0 | - |

2. set A

   - Add key A to the cache. The first added key has order 1.
     | Order | Key |
     | ----- | --- |
     | 1 | A |

3. set B

   - Add key B. The newer B is added with order 2.
     | Order | Key |
     | ----- | --- |
     | 1 | A |
     | 2 | B |

4. get A

   - Retrieve key A. The order remains unchanged.
     | Order | Key |
     | ----- | --- |
     | 1 | A |
     | 2 | B |

5. set C

   - Add key C. The new entry is added.
     | Order | Key |
     | ----- | --- |
     | 1 | A |
     | 2 | B |
     | 3 | C |

6. set D (A evicted due to FIFO)

   - To add the new key D, space is needed in the cache (maxSize: 3). Since A was the first inserted, it is evicted.
     | Order | Key |
     | ----- | --- |
     | 2 | B |
     | 3 | C |
     | 4 | D |

## 4. Suitable Use Cases

FIFO Cache is suitable for situations where **the access order of data is not important**. It is particularly useful when **old data needs to be evicted but there is no special significance attached to the most recently added data**.

Examples:

- **Log Management**:  
  When caching log files or event data, it's useful to evict old logs and keep the new ones.
- **Queue Processing**:  
  When processing jobs or tasks in a queue, it is appropriate to delete the data that was processed first.
