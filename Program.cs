using Azure.Storage.Blobs;
using Azure.Storage.Queues;
using CloudVideoUploader.Services;

var builder = WebApplication.CreateBuilder(args);

// --- Azure Storage config ---
var cfg = builder.Configuration.GetSection("AzureStorage");
var blobCs = cfg["BlobConnectionString"] ?? throw new("AzureStorage:BlobConnectionString missing");
var queueCs = cfg["QueueConnectionString"] ?? throw new("AzureStorage:QueueConnectionString missing");
var container = cfg["BlobContainerName"] ?? "videos";
var queueName = cfg["QueueName"] ?? "video-processing";

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

// Ensure storage resources exist (public blobs only for easy local testing)
using (var scope = app.Services.CreateScope())
{
    var blobContainer = scope.ServiceProvider.GetRequiredService<BlobContainerClient>();
    await blobContainer.CreateIfNotExistsAsync(Azure.Storage.Blobs.Models.PublicAccessType.None);
    await blobContainer.SetAccessPolicyAsync(Azure.Storage.Blobs.Models.PublicAccessType.None);

    var q = scope.ServiceProvider.GetRequiredService<QueueClient>();
    await q.CreateIfNotExistsAsync();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseRouting();
app.UseAuthorization();
app.MapControllers();
app.Run();