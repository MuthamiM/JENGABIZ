using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DukaLedger.Api.Data;
using DukaLedger.Api.Features.Shop.Models;

namespace DukaLedger.Api.Features.Shop;

[ApiController]
[Route("shops")]
public class ShopController : ControllerBase
{
    private readonly AppDbContext _db;
    public ShopController(AppDbContext db) => _db = db;

    [HttpGet("me")]
    public async Task<IActionResult> GetMyShop([FromHeader(Name = "X-Shop-Id")] Guid shopId)
    {
        var shop = await _db.Shops.FirstOrDefaultAsync(s => s.Id == shopId && !s.IsDeleted);
        if (shop == null) return NotFound("Duka halijapatikana");
        return Ok(shop);
    }

    [HttpPost("me/publish")]
    public async Task<IActionResult> PublishShop([FromHeader(Name = "X-Shop-Id")] Guid shopId)
    {
        var shop = await _db.Shops.FirstOrDefaultAsync(s => s.Id == shopId);
        if (shop == null) return NotFound();
        shop.IsPublished = true;
        shop.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(shop);
    }
}
