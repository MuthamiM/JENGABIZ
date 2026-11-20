namespace DukaLedger.Api.Features.Credit.Models;

public class CustomerModel
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ShopId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Phone { get; set; } = string.Empty;
    public decimal CreditLimit { get; set; } = 1000m;
    public decimal CurrentBalance { get; set; } = 0m;
    public bool IsDeleted { get; set; } = false;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}

public class PaymentModel
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid CustomerId { get; set; }
    public decimal Amount { get; set; }
    public string Method { get; set; } = "cash"; // cash, mpesa
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
