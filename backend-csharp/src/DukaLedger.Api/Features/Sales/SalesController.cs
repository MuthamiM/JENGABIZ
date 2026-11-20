using Microsoft.AspNetCore.Mvc;
using DukaLedger.Api.Data;
using DukaLedger.Api.Features.Sales.Models;

namespace DukaLedger.Api.Features.Sales;

[ApiController]
[Route("sales")]
public class SalesController : ControllerBase
{
    private readonly AppDbContext _db;
    public SalesController(AppDbContext db) => _db = db;

    [HttpPost]
    public async Task<IActionResult> RecordSale([FromBody] SaleModel sale)
    {
        sale.CreatedAt = DateTime.UtcNow;
        _db.Sales.Add(sale);
        await _db.SaveChangesAsync();
        return Ok(sale);
    }
}
