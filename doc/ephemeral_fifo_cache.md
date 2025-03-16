# Ephemeral FIFO Cache

## 1. Introduction

The Ephemeral FIFO (First In, First Out) Cache is a class that implements a **FIFO-based cache** with an **ephemeral property**. This means that the data is immediately removed from the cache once it is retrieved.

### **Note**

- **Retrieved data cannot be reused (it is deleted after access)**
- **If you need to retain the key after access, use `FIFOCache` instead**

## 2. How Ephemeral FIFO Cache Works

### 2.1 Basic Concepts

The Ephemeral FIFO Cache consists of the following elements:

- **Key**: A value used to uniquely identify data in the cache.
- **Value**: The actual data stored in the cache.
- **Order**: The order in which data was inserted into the cache. The oldest data is removed first.

### 2.2 Eviction Policy

The eviction policy of the Ephemeral FIFO Cache follows these rules:

1. **Remove the oldest data**  
   When the cache becomes full, the oldest entry (the one inserted first) is removed.
2. **Remove data upon retrieval**  
   Retrieved data is immediately removed from the cache and cannot be reused.

## 3. Workflow

### 3.1 Retrieving Data (`get` operation)

1. If the key exists:
   - Return the value.
   - After returning, the retrieved key is removed from the cache.
2. If the key does not exist:
   - Return `null`.

### 3.2 Inserting Data (`set` operation)

1. If the key already exists:
   - Update the value.
   - The updated key is treated as the "most recently added data" but its order does not change.
2. If the key does not exist:
   - If the cache exceeds the `[maxSize]`, the oldest data is removed based on the FIFO policy.
   - Add the new key-value pair to the cache.

### 3.3 Example: Ephemeral FIFO Cache Operations and State Changes

1. Initial State: EphemeralFIFOCache<maxCount: 3>

   - The cache is empty.
     | Order | Key |
     | ----- | --- |
     | 0 | - |

2. set A

   - Add key A to the cache. It is the first key, so it gets order 1.
     | Order | Key |
     | ----- | --- |
     | 1 | A |

3. set B

   - Add key B. It is the next key, so it gets order 2.
     | Order | Key |
     | ----- | --- |
     | 1 | A |
     | 2 | B |

4. get A (A evicted due to Ephemeral)

   - Retrieve key A. A is removed from the cache.
     | Order | Key |
     | ----- | --- |
     | 2 | B |

5. set C

   - Add key C. The new entry C is added.
     | Order | Key |
     | ----- | --- |
     | 2 | B |
     | 3 | C |

6. set D

   - Add key D. The new entry D is added.
     | Order | Key |
     | ----- | --- |
     | 2 | B |
     | 3 | C |
     | 4 | D |

7. set E (B evicted due to FIFO)

   - Add key E. To make room, the oldest entry B is removed due to the FIFO eviction policy (maxSize: 3).
     | Order | Key |
     | ----- | --- |
     | 3 | C |
     | 4 | D |
     | 5 | E |

## 4. Suitable Use Cases

The Ephemeral FIFO Cache is suitable when **data is used only once and then discarded**. It is ideal for cases where data is retrieved but not reused after access.

Examples:

- **One-time data processing**:  
  In scenarios where data retrieved during a one-time request or transaction is not reused and should be discarded immediately after use.
