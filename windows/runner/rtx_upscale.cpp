// Local still-image RTX VSR worker. No SDK, Python or external DLL required.
// Driver extension protocol reference (BSD-3-Clause): Chromium
// ui/gl/swap_chain_presenter.cc, ToggleNvidiaVpSuperResolution.
// https://chromium.googlesource.com/chromium/src/+/main/ui/gl/swap_chain_presenter.cc
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

using Microsoft::WRL::ComPtr;

static bool Check(HRESULT hr, const char* step) {
  if (SUCCEEDED(hr)) return true;
  std::fprintf(stderr, "%s (HRESULT 0x%08lX)\n", step,
               static_cast<unsigned long>(hr));
  return false;
}
#define CHECK(expr, step) if (!Check((expr), (step))) return false

static bool ProcessImage(const wchar_t* input, const wchar_t* output, UINT scale) {
  ComPtr<IWICImagingFactory> wic;
  CHECK(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&wic)), "WIC initialization failed");
  ComPtr<IWICBitmapDecoder> decoder;
  CHECK(wic->CreateDecoderFromFilename(input, nullptr, GENERIC_READ,
                                      WICDecodeMetadataCacheOnDemand, &decoder),
        "Cannot decode source image");
  ComPtr<IWICBitmapFrameDecode> frame;
  CHECK(decoder->GetFrame(0, &frame), "Cannot read image frame");
  UINT width = 0, height = 0;
  CHECK(frame->GetSize(&width, &height), "Cannot read image dimensions");
  const UINT out_width = width * scale, out_height = height * scale;
  if (!width || !height || width > 4096 || height > 4096 ||
      out_width > 8192 || out_height > 8192 ||
      static_cast<uint64_t>(out_width) * out_height > 32ULL * 1024 * 1024) {
    std::fprintf(stderr, "Image too large: input max 4096, output max 8192 / 32 MP\n");
    return false;
  }
  ComPtr<IWICFormatConverter> converter;
  CHECK(wic->CreateFormatConverter(&converter), "Cannot create image converter");
  CHECK(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
                              WICBitmapDitherTypeNone, nullptr, 0,
                              WICBitmapPaletteTypeCustom), "Cannot convert to BGRA");
  // NV12 needs even dimensions. Pad odd edges; source rectangle crops padding.
  const UINT tex_width = (width + 1) & ~1u, tex_height = (height + 1) & ~1u;
  std::vector<BYTE> pixels(static_cast<size_t>(tex_width) * tex_height * 4);
  CHECK(converter->CopyPixels(nullptr, tex_width * 4,
                              static_cast<UINT>(pixels.size()), pixels.data()),
        "Cannot read source pixels");
  bool has_alpha = false;
  for (UINT y = 0; y < height; ++y) {
    for (UINT x = 0; x < width; ++x) {
      has_alpha = has_alpha || pixels[(static_cast<size_t>(y) * tex_width + x) * 4 + 3] != 255;
    }
    if (tex_width != width) {
      std::memcpy(&pixels[(static_cast<size_t>(y) * tex_width + width) * 4],
                  &pixels[(static_cast<size_t>(y) * tex_width + width - 1) * 4], 4);
    }
  }
  if (tex_height != height) {
    std::memcpy(&pixels[static_cast<size_t>(height) * tex_width * 4],
                &pixels[static_cast<size_t>(height - 1) * tex_width * 4], tex_width * 4);
  }

  ComPtr<IDXGIFactory1> factory;
  CHECK(CreateDXGIFactory1(IID_PPV_ARGS(&factory)), "DXGI initialization failed");
  ComPtr<IDXGIAdapter1> adapter;
  for (UINT index = 0; ; ++index) {
    ComPtr<IDXGIAdapter1> candidate;
    if (factory->EnumAdapters1(index, &candidate) == DXGI_ERROR_NOT_FOUND) break;
    if (!candidate) continue;
    DXGI_ADAPTER_DESC1 desc{};
    if (SUCCEEDED(candidate->GetDesc1(&desc)) && desc.VendorId == 0x10DE &&
        !(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
      adapter = candidate;
      break;
    }
  }
  if (!adapter) {
    std::fprintf(stderr, "No NVIDIA GPU found. RTX VSR requires a supported NVIDIA RTX GPU.\n");
    return false;
  }
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  CHECK(D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
                          D3D11_CREATE_DEVICE_VIDEO_SUPPORT | D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                          nullptr, 0, D3D11_SDK_VERSION, &device, nullptr, &context),
        "Cannot create NVIDIA D3D11 device");
  ComPtr<ID3D11VideoDevice> video_device;
  ComPtr<ID3D11VideoContext> video_context;
  CHECK(device.As(&video_device), "D3D11 video device unavailable");
  CHECK(context.As(&video_context), "D3D11 video context unavailable");

  // First convert BGRA to NV12, then apply VSR to NV12 -> BGRA.
  // The NVIDIA driver path used by browsers is a video (not RGB texture) path.
  D3D11_TEXTURE2D_DESC texture_desc{};
  texture_desc.Width = tex_width;
  texture_desc.Height = tex_height;
  texture_desc.MipLevels = 1;
  texture_desc.ArraySize = 1;
  texture_desc.SampleDesc.Count = 1;
  texture_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  texture_desc.BindFlags = D3D11_BIND_RENDER_TARGET;
  D3D11_SUBRESOURCE_DATA source_data{pixels.data(), tex_width * 4, 0};
  ComPtr<ID3D11Texture2D> source;
  CHECK(device->CreateTexture2D(&texture_desc, &source_data, &source), "Cannot upload source image");
  texture_desc.Format = DXGI_FORMAT_NV12;
  ComPtr<ID3D11Texture2D> nv12;
  CHECK(device->CreateTexture2D(&texture_desc, nullptr, &nv12), "Cannot allocate NV12 image");
  texture_desc.Width = out_width;
  texture_desc.Height = out_height;
  texture_desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  ComPtr<ID3D11Texture2D> result;
  CHECK(device->CreateTexture2D(&texture_desc, nullptr, &result), "Cannot allocate RTX output");

  for (int pass = 0; pass < 2; ++pass) {
    const bool upscale = pass == 1;
    D3D11_VIDEO_PROCESSOR_CONTENT_DESC desc{};
    desc.InputFrameFormat = D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE;
    desc.InputFrameRate = {30, 1};
    desc.OutputFrameRate = {30, 1};
    desc.InputWidth = tex_width;
    desc.InputHeight = tex_height;
    desc.OutputWidth = upscale ? out_width : tex_width;
    desc.OutputHeight = upscale ? out_height : tex_height;
    desc.Usage = D3D11_VIDEO_USAGE_PLAYBACK_NORMAL;
    ComPtr<ID3D11VideoProcessorEnumerator> enumerator;
    CHECK(video_device->CreateVideoProcessorEnumerator(&desc, &enumerator), "Video processor unavailable");
    ComPtr<ID3D11VideoProcessor> processor;
    CHECK(video_device->CreateVideoProcessor(enumerator.Get(), 0, &processor), "Cannot create video processor");
    if (upscale) {
      constexpr GUID kNvidiaPpe = {0xd43ce1b3, 0x1f4b, 0x48ac,
          {0xba, 0xee, 0xc3, 0xc2, 0x53, 0x75, 0xe6, 0xf7}};
      struct { UINT version; UINT method; UINT enable; } extension{1, 2, 1};
      CHECK(video_context->VideoProcessorSetStreamExtension(processor.Get(), 0,
              &kNvidiaPpe, sizeof(extension), &extension),
            "RTX VSR unavailable. Update NVIDIA driver and enable Video Super Resolution in NVIDIA settings");
    }
    video_context->VideoProcessorSetStreamAutoProcessingMode(processor.Get(), 0, FALSE);
    video_context->VideoProcessorSetStreamFrameFormat(processor.Get(), 0,
                                                      D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE);
    const RECT source_rect{0, 0, static_cast<LONG>(upscale ? width : tex_width),
                                   static_cast<LONG>(upscale ? height : tex_height)};
    const RECT dest_rect{0, 0, static_cast<LONG>(desc.OutputWidth), static_cast<LONG>(desc.OutputHeight)};
    video_context->VideoProcessorSetStreamSourceRect(processor.Get(), 0, TRUE, &source_rect);
    video_context->VideoProcessorSetStreamDestRect(processor.Get(), 0, TRUE, &dest_rect);
    video_context->VideoProcessorSetOutputTargetRect(processor.Get(), TRUE, &dest_rect);
    D3D11_VIDEO_PROCESSOR_COLOR_SPACE rgb{};
    rgb.Nominal_Range = 2;  // Full-range RGB.
    D3D11_VIDEO_PROCESSOR_COLOR_SPACE yuv{};
    yuv.YCbCr_Matrix = 1;  // BT.709 limited-range NV12.
    yuv.Nominal_Range = 1;
    video_context->VideoProcessorSetStreamColorSpace(processor.Get(), 0, upscale ? &yuv : &rgb);
    video_context->VideoProcessorSetOutputColorSpace(processor.Get(), upscale ? &rgb : &yuv);
    D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC input_desc{};
    input_desc.ViewDimension = D3D11_VPIV_DIMENSION_TEXTURE2D;
    ComPtr<ID3D11VideoProcessorInputView> input_view;
    CHECK(video_device->CreateVideoProcessorInputView(upscale ? nv12.Get() : source.Get(),
            enumerator.Get(), &input_desc, &input_view), "Cannot create processor input view");
    D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC output_desc{};
    output_desc.ViewDimension = D3D11_VPOV_DIMENSION_TEXTURE2D;
    ComPtr<ID3D11VideoProcessorOutputView> output_view;
    CHECK(video_device->CreateVideoProcessorOutputView(upscale ? result.Get() : nv12.Get(),
            enumerator.Get(), &output_desc, &output_view), "Cannot create processor output view");
    D3D11_VIDEO_PROCESSOR_STREAM stream{};
    stream.Enable = TRUE;
    stream.pInputSurface = input_view.Get();
    // Never retry with VSR disabled: that would silently return ordinary scaling.
    CHECK(video_context->VideoProcessorBlt(processor.Get(), output_view.Get(), 0, 1, &stream),
          upscale ? "RTX processing failed" : "NV12 conversion failed");
  }
  texture_desc.BindFlags = 0;
  texture_desc.Usage = D3D11_USAGE_STAGING;
  texture_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  ComPtr<ID3D11Texture2D> staging;
  CHECK(device->CreateTexture2D(&texture_desc, nullptr, &staging), "Cannot allocate readback image");
  context->CopyResource(staging.Get(), result.Get());
  D3D11_MAPPED_SUBRESOURCE mapped{};
  CHECK(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped), "Cannot read RTX result");
  std::vector<BYTE> out_pixels(static_cast<size_t>(out_width) * out_height * 4);
  for (UINT y = 0; y < out_height; ++y) {
    std::memcpy(&out_pixels[static_cast<size_t>(y) * out_width * 4],
                static_cast<const BYTE*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch,
                out_width * 4);
  }
  context->Unmap(staging.Get(), 0);
  // VSR is RGB-only. Preserve transparency via independently resampled alpha.
  std::vector<BYTE> alpha_pixels;
  if (has_alpha) {
    ComPtr<IWICBitmapScaler> scaler;
    CHECK(wic->CreateBitmapScaler(&scaler), "Cannot create alpha scaler");
    CHECK(scaler->Initialize(converter.Get(), out_width, out_height,
                             WICBitmapInterpolationModeFant), "Cannot resize alpha channel");
    alpha_pixels.resize(out_pixels.size());
    CHECK(scaler->CopyPixels(nullptr, out_width * 4, static_cast<UINT>(alpha_pixels.size()),
                              alpha_pixels.data()), "Cannot read resized alpha");
  }
  for (size_t i = 3; i < out_pixels.size(); i += 4) {
    out_pixels[i] = has_alpha ? alpha_pixels[i] : 255;
  }
  ComPtr<IWICStream> file;
  CHECK(wic->CreateStream(&file), "Cannot create output stream");
  CHECK(file->InitializeFromFilename(output, GENERIC_WRITE), "Cannot open output file");
  ComPtr<IWICBitmapEncoder> encoder;
  CHECK(wic->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder), "PNG encoder unavailable");
  CHECK(encoder->Initialize(file.Get(), WICBitmapEncoderNoCache), "Cannot initialize PNG encoder");
  ComPtr<IWICBitmapFrameEncode> encoded_frame;
  CHECK(encoder->CreateNewFrame(&encoded_frame, nullptr), "Cannot create PNG frame");
  CHECK(encoded_frame->Initialize(nullptr), "Cannot initialize PNG frame");
  CHECK(encoded_frame->SetSize(out_width, out_height), "Cannot set PNG dimensions");
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  CHECK(encoded_frame->SetPixelFormat(&format), "Cannot set PNG format");
  if (format != GUID_WICPixelFormat32bppBGRA) return false;
  CHECK(encoded_frame->WritePixels(out_height, out_width * 4,
          static_cast<UINT>(out_pixels.size()), out_pixels.data()), "Cannot encode PNG pixels");
  CHECK(encoded_frame->Commit(), "Cannot commit PNG frame");
  CHECK(encoder->Commit(), "Cannot commit PNG file");
  return true;
}

int wmain(int argc, wchar_t* argv[]) {
  if (argc != 4 || (wcscmp(argv[3], L"2") != 0 && wcscmp(argv[3], L"4") != 0)) {
    std::fprintf(stderr, "Usage: rtx_upscale.exe input output 2|4\n");
    return 2;
  }
  if (!Check(CoInitializeEx(nullptr, COINIT_MULTITHREADED), "COM initialization failed")) return 1;
  const bool success = ProcessImage(argv[1], argv[2], static_cast<UINT>(_wtoi(argv[3])));
  CoUninitialize();
  return success ? 0 : 1;
}
