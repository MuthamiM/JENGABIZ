using Xunit;
using DukaLedger.Api.Features.Shop.Models;

namespace DukaLedger.Tests.Features;

public class ShopTests
{
    [Fact]
    public void Shop_DefaultProfileType_IsDuka()
    {
        var shop = new ShopModel();
        Assert.Equal("duka", shop.ProfileType);
    }
}
