package com.dukaledger.api.features.sync;

import org.springframework.web.bind.annotation.*;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/sync")
public class SyncController {
    @GetMapping("/pull")
    public Map<String, Object> pullSync(@RequestParam UUID shopId, @RequestParam(required = false) Instant since) {
        return Map.of(
            "server_timestamp", Instant.now(),
            "items", List.of(),
            "customers", List.of(),
            "sales", List.of()
        );
    }
}
