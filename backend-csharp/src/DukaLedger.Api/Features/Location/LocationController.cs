using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DukaLedger.Api.Data;
using DukaLedger.Api.Features.Location.Models;

namespace DukaLedger.Api.Features.Location;

[ApiController]
[Route("locations")]
public class LocationController : ControllerBase
{
    private readonly AppDbContext _db;
    public LocationController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<IActionResult> GetLocations([FromQuery] string? county)
    {
        var query = _db.Locations.AsQueryable();
        if (!string.IsNullOrEmpty(county))
            query = query.Where(l => l.County == county);
        return Ok(await query.Take(100).ToListAsync());
    }
}
