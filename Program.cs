using Azure.Storage.Blobs;
using Azure.Storage.Queues;
using CloudVideoUploader.Services;
using Azure.Identity;
using Azure.Storage.Blobs;

var builder = WebApplication.CreateBuilder(args);

// --- Azure Storage config ---
var cfg = builder.Configuration.GetSection("AzureStorage");
var blobCs = cfg["BlobConnectionString"] ?? throw new("AzureStorage:BlobConnectionString missing");
var queueCs = cfg["QueueConnectionString"] ?? throw new("AzureStorage:QueueConnectionString missing");
var container = cfg["BlobContainerName"] ?? "videos";
var queueName = cfg["QueueName"] ?? "video-processing";

string? conn = Environment.GetEnvironmentVariable("AZURE_STORAGE_CONNECTION_STRING");
string? accountUrl = Environment.GetEnvironmentVariable("STORAGE_ACCOUNT_URL");
// e.g. https://mystorageaccount.blob.core.windows.net

BlobServiceClient blobClient = conn switch
{
    { Length: > 0 } => new BlobServiceClient(conn),
    _ when !string.IsNullOrWhiteSpace(accountUrl) => new BlobServiceClient(new Uri(accountUrl), new DefaultAzureCredential()),
    _ => throw new InvalidOperationException("No storage config found: set AZURE_STORAGE_CONNECTION_STRING or STORAGE_ACCOUNT_URL."),
};

// SDK clients
builder.Services.AddSingleton(new BlobServiceClient(blobCs));
builder.Services.AddSingleton(new QueueServiceClient(queueCs));

// Typed clients for our container/queue
builder.Services.AddSingleton(sp =>
    sp.GetRequiredService<BlobServiceClient>().GetBlobContainerClient(container));
builder.Services.AddSingleton(sp =>
    sp.GetRequiredService<QueueServiceClient>().GetQueueClient(queueName));

// App services
builder.Services.AddSingleton<VideoService>();
builder.Services.AddHostedService<VideoProcessor>();

// MVC / Swagger
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();
app.MapGet("/health", () => Results.Ok("OK")).AllowAnonymous();


// Ensure storage resources exist (  public blobs only for easy local testing)
using (var scope = app.Services.CreateScope())
{
    var blobContainer = scope.ServiceProvider.GetRequiredService<BlobContainerClient>();
    await blobContainer.CreateIfNotExistsAsync(Azure.Storage.Blobs.Models.PublicAccessType.None);
    await blobContainer.SetAccessPolicyAsync(Azure.Storage.Blobs.Models.PublicAccessType.None);

    var q = scope.ServiceProvider.GetRequiredService<QueueClient>();
    await q.CreateIfNotExistsAsync();
}


app.UseSwagger();
app.UseSwaggerUI();


app.UseRouting();
app.UseAuthorization();
app.MapControllers();
app.Run();