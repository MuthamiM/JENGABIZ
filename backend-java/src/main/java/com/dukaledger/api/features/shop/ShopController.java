package com.dukaledger.api.features.shop;

import com.dukaledger.api.features.shop.model.Shop;
import org.springframework.web.bind.annotation.*;
import java.util.UUID;

@RestController
@RequestMapping("/shops")
public class ShopController {
    @GetMapping("/me")
    public Shop getMyShop(@RequestHeader("X-Shop-Id") UUID shopId) {
        Shop shop = new Shop();
        shop.setId(shopId);
        shop.setName("Duka Bora");
        return shop;
    }

    @PostMapping("/me/publish")
    public Shop publishShop(@RequestHeader("X-Shop-Id") UUID shopId) {
        Shop shop = new Shop();
        shop.setId(shopId);
        shop.setPublished(true);
        return shop;
    }
}
