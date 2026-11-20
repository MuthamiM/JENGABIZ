package com.dukaledger.api.features.location.model;

import jakarta.persistence.*;
import lombok.*;
import java.util.UUID;

@Entity
@Table(name = "locations")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class Location {
    @Id
    private UUID id = UUID.randomUUID();
    private String county;
    private String area;
    private String estate;
}
