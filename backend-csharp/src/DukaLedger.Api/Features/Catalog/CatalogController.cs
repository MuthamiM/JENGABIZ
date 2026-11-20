using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DukaLedger.Api.Data;
using DukaLedger.Api.Features.Catalog.Models;

namespace DukaLedger.Api.Features.Catalog;

[ApiController]
[Route("catalog")]
public class CatalogController : ControllerBase
{
    private readonly AppDbContext _db;
    public CatalogController(AppDbContext db) => _db = db;

    [HttpGet("items")]
    public async Task<IActionResult> GetItems([FromQuery] Guid shopId)
    {
        var items = await _db.Items.Where(i => i.ShopId == shopId && !i.IsDeleted).ToListAsync();
        return Ok(items);
    }

    [HttpPost("items")]
    public async Task<IActionResult> CreateItem([FromBody] ItemModel item)
    {
        item.UpdatedAt = DateTime.UtcNow;
        _db.Items.Add(item);
        await _db.SaveChangesAsync();
        return Created($"/catalog/items/{item.Id}", item);
    }
}
