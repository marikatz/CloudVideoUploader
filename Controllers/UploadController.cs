using CloudVideoUploader.Services;
using Microsoft.AspNetCore.Mvc;

namespace CloudVideoUploader.Controllers;

[ApiController]
[Route("api/[controller]")]
public class VideosController : ControllerBase
{
    private readonly VideoService _videos;

    public VideosController(VideoService videos) => _videos = videos;

    // POST api/videos (multipart/form-data; key: file, optional: name)
    [HttpPost]
    [RequestSizeLimit(long.MaxValue)]
    public async Task<IActionResult> Upload(IFormFile file, string? name, CancellationToken ct)
    {
        if (file is null || file.Length == 0) return BadRequest("Missing file");

        var fileName = string.IsNullOrWhiteSpace(name) ? file.FileName : name;
        await using var s = file.OpenReadStream();

        var url = await _videos.UploadAsync(fileName, s, file.ContentType, ct);
        return Ok(new { name = fileName, url });
    }

    // GET api/videos/{name}  -> streams from Azurite via API
    [HttpGet("{name}")]
    public async Task<IActionResult> Get(string name, CancellationToken ct)
    {
        var res = await _videos.DownloadAsync(name, ct);
        if (res is null) return NotFound();
        return File(res.Value.Content, res.Value.ContentType, enableRangeProcessing: true);
    }
}