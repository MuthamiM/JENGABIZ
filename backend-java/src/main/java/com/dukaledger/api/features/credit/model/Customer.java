package com.dukaledger.api.features.credit.model;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "customers")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class Customer {
    @Id
    private UUID id = UUID.randomUUID();
    private UUID shopId;
    private String name;
    private String phone;
    private BigDecimal creditLimit = new BigDecimal("1000.00");
    private BigDecimal currentBalance = BigDecimal.ZERO;
    private boolean isDeleted = false;
    private Instant updatedAt = Instant.now();
}
