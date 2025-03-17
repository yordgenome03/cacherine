# LFU Cache

## 1. Introduction

LFU (Least Frequently Used) Cache is a cache replacement algorithm that prioritizes removing data with the least access frequency.

## 2. LFU Cache Mechanism

### 2.1 Basic Concepts

An LFU Cache consists of the following elements:

- **Key**: A value used to uniquely identify the data in the cache.
- **Value**: The data stored in the cache.
- **Frequency Counter**: A counter that tracks the access frequency of each key.

### 2.2 Eviction Policy

The LFU Cache eviction policy follows these rules:

1. **Remove the data with the lowest frequency**
   - When the cache is full, the entry with the minimum access count is evicted.
2. **FIFO for entries with the same frequency**
   - If multiple entries have the same frequency, the oldest entry is evicted.

## 3. Workflow

### 3.1 Data Retrieval (`get` operation)

1. If the key exists:
   - Return the value.
   - Increment the frequency counter.
2. If the key does not exist:
   - Return `null`.

### 3.2 Data Insertion (`set` operation)

1. If the key exists:
   - Update the value.
   - Increment the frequency counter.
2. If the key does not exist:
   - If the cache exceeds the [maxSize], evict entries based on LFU policy.
   - Add the new key-value pair and initialize the frequency counter to 1.

### 3.3 Example: LFUCache operations and state changes

1. Initial state: LFUCache<maxCount: 3>

   - The cache is empty.
     | index | Key | Frequency Count |
     | ----- | --- | --------------- |
     | 0 | - | - |

2. set A

   - Key A is added to the cache. The frequency count is 1 on the first insertion.
     | index | Key | Frequency Count |
     |-------|-----|-----------------|
     | 0 | A | 1 |

3. set B

   - Key B is added. The order determines that B is the newer entry.
     | Order | Key | Frequency Count |
     |-------|-----|-----------------|
     | 0 | A | 1 |
     | 1 | B | 1 |

4. get A

   - Key A is accessed. The frequency count increases to 2.
     | Order | Key | Frequency Count |
     |-------|-----|-----------------|
     | 0 | A | 2 |
     | 1 | B | 1 |

5. set C

   - Key C is added. A new entry is inserted.
     | Order | Key | Frequency Count |
     |-------|-----|-----------------|
     | 0 | A | 2 |
     | 1 | B | 1 |
     | 2 | C | 1 |

6. set D (B evicted due to LFU)

   - A new key D is added, requiring space in the cache (maxSize: 3). B and C have the same frequency of 1, but B is evicted because it was inserted first.
     | Order | Key | Frequency Count |
     |-------|-----|-----------------|
     | 1 | A | 2 |
     | 3 | C | 1 |
     | 4 | D | 1 |

## 4. Suitable Use Cases

LFU Cache is especially effective in the following scenarios:

1. When there is a need to prioritize data based on access frequency

   - LFU Cache is most effective when there is a large variation in the frequency of data access. It prioritizes keeping the most frequently accessed data and evicts less frequently used data, making it ideal for scenarios where you want to cache "commonly used data for a long time."

   Examples:

   - API response caching: Keep frequently requested API responses while evicting less frequently requested ones.
   - Content Management System (CMS): Cache frequently accessed content (e.g., articles, images) and evict less frequently accessed items.

2. When access frequency fluctuates over time

   - LFU Cache is useful when the frequency of data access changes dynamically over time. It tracks access frequency and adds data with increasing frequency while evicting data that becomes less frequently accessed.

   Examples:

   - News sites: Articles' access frequency fluctuates based on time of day or events. LFU Cache can keep the most read articles and evict old ones.
   - Online stores: Cache data dynamically based on the frequency of access for new products or sale items.

3. When users or systems often request items based on past data usage

   - LFU Cache is beneficial when prioritizing data based on historical access patterns. It uses "past access frequency" to manage data, keeping the most in-demand data.

   Examples:

   - Recently accessed files caching: Cache files or documents that users frequently access and evict those not accessed in a long time.
   - History-based applications: Cache user settings or pages that are frequently used and evict unused ones.
