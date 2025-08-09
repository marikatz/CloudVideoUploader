using Azure.Storage.Queues;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using System.Text.Json;

namespace CloudVideoUploader.Services;

public class VideoProcessor : BackgroundService
{
    private readonly QueueClient _queue;
    private readonly BlobContainerClient _container;
    private readonly ILogger<VideoProcessor> _logger;

    public VideoProcessor(QueueClient queue, BlobContainerClient container, ILogger<VideoProcessor> logger)
    {
        _queue = queue;
        _container = container;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("VideoProcessor started.");

        // Ensure queue & container exist
        await _queue.CreateIfNotExistsAsync();
        await _container.CreateIfNotExistsAsync(PublicAccessType.None);

        while (!stoppingToken.IsCancellationRequested)
        {
            var messages = await _queue.ReceiveMessagesAsync(maxMessages: 1, visibilityTimeout: TimeSpan.FromSeconds(30), cancellationToken: stoppingToken);

            if (messages.Value.Length == 0)
            {
                await Task.Delay(1000, stoppingToken);
                continue;
            }

            foreach (var message in messages.Value)
            {
                try
                {
                    var payload = JsonSerializer.Deserialize<UploadMsg>(message.MessageText);

                    if (payload != null)
                    {
                        _logger.LogInformation("Processing blob: {BlobName}", payload.blobName);

                        // Create metadata
                        var meta = new
                        {
                            payload.blobName,
                            processedUtc = DateTime.UtcNow
                        };

                        var target = _container.GetBlobClient($"{payload.blobName}.metadata.json");
                        await target.UploadAsync(BinaryData.FromObjectAsJson(meta), overwrite: true, cancellationToken: stoppingToken);
                    }

                    // Delete the processed message
                    await _queue.DeleteMessageAsync(message.MessageId, message.PopReceipt, stoppingToken);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error processing message");
                }
            }
        }
    }

    private record UploadMsg(string blobName, string container, DateTime uploadedUtc);
}
