package com.dukaledger.api.features.catalog.model;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "items")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class Item {
    @Id
    private UUID id = UUID.randomUUID();
    private UUID shopId;
    private String name;
    private String unit = "pcs"; // kg, bunches, heaps, cups, ml
    private BigDecimal buyPrice = BigDecimal.ZERO;
    private BigDecimal sellPrice = BigDecimal.ZERO;
    private int quantity = 0;
    private int lowStockLevel = 5;
    private boolean isDeleted = false;
    private Instant updatedAt = Instant.now();
}
