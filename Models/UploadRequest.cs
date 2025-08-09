public class UploadRequest
{
    public IFormFile File { get; set; } = default!;
    public string? Name { get; set; }
}