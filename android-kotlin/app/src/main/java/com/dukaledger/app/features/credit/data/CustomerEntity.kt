package com.dukaledger.app.features.credit.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(tableName = "customers")
data class CustomerEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val shopId: String,
    val name: String,
    val phone: String,
    val creditLimit: Double = 1000.0,
    val currentBalance: Double = 0.0,
    val trustScore: String = "Normal",
    val notes: String? = null,
    val updatedAt: Long = System.currentTimeMillis(),
    val isDeleted: Boolean = false
)
