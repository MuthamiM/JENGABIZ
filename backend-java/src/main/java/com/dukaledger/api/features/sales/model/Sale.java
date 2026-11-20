package com.dukaledger.api.features.sales.model;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "sales")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class Sale {
    @Id
    private UUID id = UUID.randomUUID();
    private UUID shopId;
    private UUID customerId;
    private String type = "cash"; // cash, credit
    private BigDecimal total;
    private Instant createdAt = Instant.now();
}
