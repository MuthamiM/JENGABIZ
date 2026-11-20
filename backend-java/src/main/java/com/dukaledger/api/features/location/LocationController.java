package com.dukaledger.api.features.location;

import com.dukaledger.api.features.location.model.Location;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/locations")
public class LocationController {
    @GetMapping
    public List<Location> getLocations() {
        return List.of(new Location(java.util.UUID.randomUUID(), "Nairobi", "Kibera", "Olympic"));
    }
}
