using System.Text.Json;
using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Queues;

namespace CloudVideoUploader.Services;

public class VideoService
{
    private readonly BlobContainerClient _container;
    private readonly QueueClient _queue;

    public VideoService(BlobContainerClient container, QueueClient queue)
    {
        _container = container;
        _queue = queue;
    }

    public async Task<string> UploadAsync(string fileName, Stream content, string? contentType, CancellationToken ct = default)
    {
        var blob = _container.GetBlobClient(fileName);

        var opts = new BlobUploadOptions
        {
            HttpHeaders = new BlobHttpHeaders { ContentType = contentType ?? "application/octet-stream" }
        };

        await blob.UploadAsync(content, opts, ct);

        // Enqueue a message for downstream processing
        var msg = JsonSerializer.Serialize(new
        {
            blobName = fileName,
            container = _container.Name,
            uploadedUtc = DateTime.UtcNow
        });

        await _queue.SendMessageAsync(msg, ct);

        // Direct Azurite URL (public for local dev)
        return $"http://127.0.0.1:10000/devstoreaccount1/{_container.Name}/{Uri.EscapeDataString(fileName)}";
    }

    public async Task<(Stream Content, string ContentType)?> DownloadAsync(string fileName, CancellationToken ct = default)
    {
        var blob = _container.GetBlobClient(fileName);
        if (!await blob.ExistsAsync(ct)) return null;

        Response<BlobDownloadStreamingResult> resp = await blob.DownloadStreamingAsync(cancellationToken: ct);
        var ctType = resp.Value.Details.ContentType ?? "application/octet-stream";
        return (resp.Value.Content, ctType);
    }
}