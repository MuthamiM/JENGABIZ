package com.dukaledger.app.features.catalog.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface ItemDao {
    @Query("SELECT * FROM items WHERE shopId = :shopId AND isDeleted = 0")
    fun getItems(shopId: String): Flow<List<ItemEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertItem(item: ItemEntity)

    @Query("UPDATE items SET quantity = quantity - :qty, updatedAt = :now WHERE id = :itemId")
    suspend fun deductStock(itemId: String, qty: Int, now: Long = System.currentTimeMillis())
}
