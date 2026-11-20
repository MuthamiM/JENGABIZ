namespace DukaLedger.Api.Features.Location.Models;

public class LocationModel
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string County { get; set; } = string.Empty;
    public string Area { get; set; } = string.Empty;
    public string Estate { get; set; } = string.Empty;
}
