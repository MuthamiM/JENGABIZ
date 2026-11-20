package com.dukaledger.app.core.database

import androidx.room.Database
import androidx.room.RoomDatabase
import com.dukaledger.app.features.catalog.data.ItemEntity
import com.dukaledger.app.features.credit.data.CustomerEntity
import com.dukaledger.app.features.credit.data.CustomerDao
import com.dukaledger.app.features.catalog.data.ItemDao

@Database(entities = [ItemEntity::class, CustomerEntity::class], version = 1, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun itemDao(): ItemDao
    abstract fun customerDao(): CustomerDao
}
