using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DukaLedger.Api.Data;

namespace DukaLedger.Api.Features.Sync;

[ApiController]
[Route("sync")]
public class SyncController : ControllerBase
{
    private readonly AppDbContext _db;
    public SyncController(AppDbContext db) => _db = db;

    [HttpGet("pull")]
    public async Task<IActionResult> PullSync([FromQuery] Guid shopId, [FromQuery] DateTime? since)
    {
        var itemsQuery = _db.Items.Where(i => i.ShopId == shopId);
        var customersQuery = _db.Customers.Where(c => c.ShopId == shopId);

        if (since.HasValue)
        {
            itemsQuery = itemsQuery.Where(i => i.UpdatedAt > since.Value);
            customersQuery = customersQuery.Where(c => c.UpdatedAt > since.Value);
        }

        return Ok(new
        {
            ServerTimestamp = DateTime.UtcNow,
            Items = await itemsQuery.ToListAsync(),
            Customers = await customersQuery.ToListAsync()
        });
    }
}
