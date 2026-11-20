package com.dukaledger.app.features.catalog.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(tableName = "items")
data class ItemEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val shopId: String,
    val name: String,
    val unit: String = "pcs",
    val buyPrice: Double,
    val sellPrice: Double,
    val quantity: Int,
    val lowStockLevel: Int = 5,
    val updatedAt: Long = System.currentTimeMillis(),
    val isDeleted: Boolean = false
)
