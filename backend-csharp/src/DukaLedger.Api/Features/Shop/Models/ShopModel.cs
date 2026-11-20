namespace DukaLedger.Api.Features.Shop.Models;

public class ShopModel
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OwnerId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string ProfileType { get; set; } = "duka"; // duka or mama_mboga
    public string? PaymentNumber { get; set; }
    public Guid? LocationId { get; set; }
    public string Language { get; set; } = "sw";
    public bool IsPublished { get; set; } = false;
    public bool IsDeleted { get; set; } = false;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
