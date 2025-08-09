namespace CloudVideoUploader.Models
{
    public record VideoUploadResult(string FileName, string BlobUrl, string QueueMessageId);
}