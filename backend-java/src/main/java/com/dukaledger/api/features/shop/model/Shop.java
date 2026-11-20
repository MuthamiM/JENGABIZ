package com.dukaledger.api.features.shop.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "shops")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class Shop {
    @Id
    private UUID id = UUID.randomUUID();
    private UUID ownerId;
    private String name;
    private String profileType = "duka"; // duka or mama_mboga
    private String paymentNumber;
    private UUID locationId;
    private String language = "sw";
    private boolean isPublished = false;
    private boolean isDeleted = false;
    private Instant updatedAt = Instant.now();
}
