namespace DukaLedger.Api.Features.Sales.Models;

public class SaleModel
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ShopId { get; set; }
    public Guid? CustomerId { get; set; }
    public string Type { get; set; } = "cash"; // cash, credit
    public decimal Total { get; set; }
    public string ItemsJson { get; set; } = "[]";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
