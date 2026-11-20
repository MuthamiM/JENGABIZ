namespace DukaLedger.Api.Features.Catalog.Models;

public class ItemModel
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ShopId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Unit { get; set; } = "pcs"; // kg, bunches, heaps, cups, ml
    public decimal BuyPrice { get; set; }
    public decimal SellPrice { get; set; }
    public int Quantity { get; set; }
    public int LowStockLevel { get; set; } = 5;
    public bool IsDeleted { get; set; } = false;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
