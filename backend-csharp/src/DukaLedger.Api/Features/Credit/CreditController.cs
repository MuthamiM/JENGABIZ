using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DukaLedger.Api.Data;
using DukaLedger.Api.Features.Credit.Models;

namespace DukaLedger.Api.Features.Credit;

[ApiController]
[Route("credit")]
public class CreditController : ControllerBase
{
    private readonly AppDbContext _db;
    public CreditController(AppDbContext db) => _db = db;

    [HttpGet("customers")]
    public async Task<IActionResult> GetCustomers([FromQuery] Guid shopId)
    {
        var list = await _db.Customers
            .Where(c => c.ShopId == shopId && !c.IsDeleted)
            .OrderByDescending(c => c.CurrentBalance)
            .ToListAsync();
        return Ok(list);
    }

    [HttpPost("payments")]
    public async Task<IActionResult> AddPayment([FromBody] PaymentModel payment)
    {
        var customer = await _db.Customers.FindAsync(payment.CustomerId);
        if (customer == null) return NotFound("Mteja hajapatikana");

        customer.CurrentBalance -= payment.Amount;
        customer.UpdatedAt = DateTime.UtcNow;
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync();
        return Ok(payment);
    }
}
