using Microsoft.EntityFrameworkCore;
using DukaLedger.Api.Features.Shop.Models;
using DukaLedger.Api.Features.Catalog.Models;
using DukaLedger.Api.Features.Credit.Models;
using DukaLedger.Api.Features.Sales.Models;
using DukaLedger.Api.Features.Location.Models;

namespace DukaLedger.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<ShopModel> Shops => Set<ShopModel>();
    public DbSet<ItemModel> Items => Set<ItemModel>();
    public DbSet<CustomerModel> Customers => Set<CustomerModel>();
    public DbSet<PaymentModel> Payments => Set<PaymentModel>();
    public DbSet<SaleModel> Sales => Set<SaleModel>();
    public DbSet<LocationModel> Locations => Set<LocationModel>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);
        modelBuilder.Entity<ShopModel>().HasIndex(s => s.OwnerId);
        modelBuilder.Entity<ItemModel>().HasIndex(i => i.ShopId);
        modelBuilder.Entity<CustomerModel>().HasIndex(c => c.ShopId);
        modelBuilder.Entity<SaleModel>().HasIndex(s => s.ShopId);
    }
}
