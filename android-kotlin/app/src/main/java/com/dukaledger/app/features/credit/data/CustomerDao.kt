package com.dukaledger.app.features.credit.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Dao
interface CustomerDao {
    @Query("SELECT * FROM customers WHERE shopId = :shopId AND isDeleted = 0 ORDER BY currentBalance DESC")
    fun getDebtors(shopId: String): Flow<List<CustomerEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCustomer(customer: CustomerEntity)
}
