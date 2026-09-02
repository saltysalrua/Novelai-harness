import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/core/harness/tools/novelai_inpaint_tool.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NovelAiInpaint 工具集测试', () {
    late NovelAiRepository repository;
    late ConfigService configService;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('inpaint_tool_test_');
      SharedPreferences.setMockInitialValues({
        'novelai_key': 'test-token',
        'save_directory': tempDir.path,
        'enable_stream_preview': false,
      });
      repository = NovelAiRepository();
      configService = ConfigService();

      // 生成一张测试用图并记录到历史
      final testImg = img.Image(width: 1024, height: 1024);
      img.fill(testImg, color: img.ColorRgba8(255, 0, 0, 255));
      final bytes = Uint8List.fromList(img.encodePng(testImg));

      final filePath = '${tempDir.path}/test_image.png';
      File(filePath).writeAsBytesSync(bytes);

      final generated = NaiGeneratedImage(
        id: 'test_img_1',
        bytes: bytes,
        localFilePath: filePath,
        params: const NaiGenerationParams(
          prompt: '1girl, solo',
          width: 1024,
          height: 1024,
        ),
        createdAt: DateTime.now(),
        seed: 12345,
        isOpusFree: true,
      );
      repository.addImageForTesting(generated);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('NovelAiInpaintGeometryTool 解析 BBox 并输出几何免点计算结果', () async {
      final tool = NovelAiInpaintGeometryTool(repository: repository);
      final result = await tool.execute('call_geo_1', {
        'rect': [0.2, 0.2, 0.4, 0.4], // [ymin, xmin, ymax, xmax]
        'context_padding': 64,
        'image_index': 0,
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('焦点修复几何计算结果'));
      expect(result.content, contains('API 请求尺寸'));
      expect(result.content, contains('Opus 免费'));
    });

    test('NovelAiInpaintTool 在无底图时返回友好错误提示', () async {
      final emptyRepo = NovelAiRepository();
      final tool = NovelAiInpaintTool(
        repository: emptyRepo,
        configService: configService,
        getCurrentParams: () =>
            const NaiGenerationParams(prompt: 'masterpiece'),
      );

      final result = await tool.execute('call_inpaint_1', {
        'mode': 'focus',
        'rect': [0.1, 0.1, 0.5, 0.5],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('未找到可供修复的底图'));
    });

    test('parseToolRectArg 归一化并自动纠正乱序/越界坐标', () {
      // [ymin, xmin, ymax, xmax] 乱序 + 越界
      final r = parseToolRectArg([0.9, 0.9, 0.1, 0.1]);
      expect(r.rect, const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8));
      expect(r.detectedFormat, contains('归一化'));
      // 对象写法：负值/超界/字符串数字全部容错
      final r2 = parseToolRectArg({
        'left': -0.2,
        'top': '0.3',
        'width': 0.5,
        'height': 1.2,
      });
      expect(r2.rect, const Rect.fromLTWH(0.0, 0.3, 0.3, 0.7));
      // 无法解析时报错必须携带收到的原值回显，便于定位 Agent 实际传了什么
      expect(parseToolRectArg('bad').rect, isNull);
      expect(parseToolRectArg('bad').error, contains('收到'));
      expect(parseToolRectArg([1, 2]).rect, isNull);
    });

    test('parseToolRectArg 容错字符串与多样对象/嵌套写法', () {
      // JSON 序列化数组字符串 (Agent 常把数组直接序列化成字符串传)
      final jsonArr = parseToolRectArg('[0.25, 0.5, 0.5, 0.75]');
      expect(jsonArr.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));
      expect(jsonArr.error, isNull);

      // 逗号分隔四数字符串
      final csv = parseToolRectArg('0.25, 0.5, 0.5, 0.75');
      expect(csv.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));

      // JSON 序列化对象字符串
      final jsonObj = parseToolRectArg(
        '{"left": 0.5, "top": 0.25, "width": 0.25, "height": 0.25}',
      );
      expect(jsonObj.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));

      // {ymin, xmin, ymax, xmax} 对象键名 (与数组同位序)
      final bboxObj = parseToolRectArg({
        'ymin': 0.25,
        'xmin': 0.5,
        'ymax': 0.5,
        'xmax': 0.75,
      });
      expect(bboxObj.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));

      // {x1, y1, x2, y2} 对象键名
      final xyObj = parseToolRectArg({
        'x1': 0.5,
        'y1': 0.25,
        'x2': 0.75,
        'y2': 0.5,
      });
      expect(xyObj.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));

      // 嵌套两点写法 [[x1, y1], [x2, y2]]
      final nested = parseToolRectArg([
        [0.5, 0.25],
        [0.75, 0.5],
      ]);
      expect(nested.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));

      // 百分比也能走字符串/对象键名写法
      final pctStr = parseToolRectArg('25%, 50%, 50%, 75%');
      expect(pctStr.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));
      expect(pctStr.detectedFormat, contains('百分比'));
    });

    test('parseToolRectArg 自动识别百分比坐标 (批注工具体系)', () {
      // Agent 常把 add_image_annotation 的百分比坐标直接抄给修复工具
      final arr = parseToolRectArg([
        25.0,
        50.0,
        50.0,
        75.0,
      ]); // ymin,xmin,ymax,xmax 百分比
      expect(arr.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));
      expect(arr.detectedFormat, contains('百分比'));

      // 对象写法 {left, top, width, height} 百分比 + 带 %/px 后缀字符串容错
      final obj = parseToolRectArg({
        'left': '50%',
        'top': '25%',
        'width': 25,
        'height': '25%',
      });
      expect(obj.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));
      expect(obj.error, isNull);
    });

    test('parseToolRectArg 自动识别像素坐标 (view_image_annotations 体系)', () {
      // 1024x1024 图：像素 [ymin=256, xmin=512, ymax=512, xmax=768]
      final arr = parseToolRectArg(
        [256, 512, 512, 768],
        imageWidth: 1024,
        imageHeight: 1024,
      );
      expect(arr.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));
      expect(arr.detectedFormat, contains('像素'));

      // {left, top, right, bottom} 对象写法像素坐标
      final obj = parseToolRectArg(
        {'left': 512, 'top': 256, 'right': 768, 'bottom': 512},
        imageWidth: 1024,
        imageHeight: 1024,
      );
      expect(obj.rect, const Rect.fromLTWH(0.5, 0.25, 0.25, 0.25));

      // {x, y, w, h} 像素写法 + 宽度超出图片尺寸时钳制
      final wh = parseToolRectArg(
        {'x': 512, 'y': 256, 'w': 1500, 'h': 256},
        imageWidth: 1024,
        imageHeight: 1024,
      );
      expect(wh.rect, const Rect.fromLTWH(0.5, 0.25, 0.5, 0.25));

      // 像素坐标但缺图片尺寸 → 明确报错而非钳成全图
      final noDims = parseToolRectArg([256, 512, 512, 768]);
      expect(noDims.rect, isNull);
      expect(noDims.error, isNotNull);
      expect(noDims.error, contains('像素坐标'));
    });

    test('resolveAnnotationSelection 批注转修复选区联动', () {
      final annotations = [
        ImageAnnotation.rect(
          id: 'r1',
          normalizedRect: const Rect.fromLTWH(0.1, 0.1, 0.4, 0.4),
          note: '修复眼睛',
        ),
        ImageAnnotation.point(
          id: 'p1',
          normalizedPoint: const Offset(0.5, 0.5),
        ),
        ImageAnnotation.global(id: 'g1', note: '整体提亮'),
      ];

      // 矩形批注直用其选区
      final rectRes = resolveAnnotationSelection(annotations, 'r1');
      expect(rectRes.error, isNull);
      expect(rectRes.rect, const Rect.fromLTWH(0.1, 0.1, 0.4, 0.4));

      // 图钉锚点 → 以锚点为中心的小选区 (12% 短边)
      final pointRes = resolveAnnotationSelection(annotations, 'p1');
      expect(pointRes.error, isNull);
      expect(pointRes.rect, const Rect.fromLTWH(0.44, 0.44, 0.12, 0.12));

      // 整图批注无具体位置 → 明确报错
      final globalRes = resolveAnnotationSelection(annotations, 'g1');
      expect(globalRes.rect, isNull);
      expect(globalRes.error, isNotNull);

      // 找不到的 ID → 明确报错 (不再静默回退修图片中心)
      final missing = resolveAnnotationSelection(annotations, 'nope');
      expect(missing.rect, isNull);
      expect(missing.error, isNotNull);
    });

    test('NovelAiInpaintTool annotation_id 不存在时明确报错', () async {
      final tool = NovelAiInpaintTool(
        repository: repository,
        configService: configService,
        getCurrentParams: () => const NaiGenerationParams(prompt: 'p'),
      );
      final result = await tool.execute('c_ann_missing', {
        'annotation_id': 'not_exist',
      });
      expect(result.isError, isTrue);
      expect(result.content, contains('未在目标图片上找到批注'));
    });

    test('NovelAiInpaintTool focus 模式无选区时报错而非静默修中心', () async {
      final tool = NovelAiInpaintTool(
        repository: repository,
        configService: configService,
        getCurrentParams: () => const NaiGenerationParams(prompt: 'p'),
      );
      final result = await tool.execute('c_no_sel', {'mode': 'focus'});
      expect(result.isError, isTrue);
      expect(result.content, contains('指定待修复区域'));
    });

    test('NovelAiInpaintTool 整图批注无法作为选区时明确报错', () async {
      final bytes = repository.history.first.bytes;
      final annotated = NaiGeneratedImage(
        id: 'test_img_global',
        bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        params: const NaiGenerationParams(
          prompt: 'p',
          width: 1024,
          height: 1024,
        ),
        createdAt: DateTime.now(),
        seed: 1,
        isOpusFree: true,
        annotations: [ImageAnnotation.global(id: 'g9', note: '全部重画')],
      );
      repository.addImageForTesting(annotated);

      final tool = NovelAiInpaintTool(
        repository: repository,
        configService: configService,
        getCurrentParams: () => const NaiGenerationParams(prompt: 'p'),
      );
      final result = await tool.execute('c_global', {'annotation_id': 'g9'});
      expect(result.isError, isTrue);
      expect(result.content, contains('整图修改意见'));
    });

    test('NovelAiInpaintGeometryTool 支持 annotation_id 且按实际字节解码尺寸', () async {
      // params 写假宽高 512，实际字节 1024x1024 —— 几何必须按实际字节算
      final bytes = repository.history.first.bytes;
      final annotated = NaiGeneratedImage(
        id: 'test_img_ann',
        bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        params: const NaiGenerationParams(prompt: 'p', width: 512, height: 512),
        createdAt: DateTime.now(),
        seed: 1,
        isOpusFree: true,
        annotations: [
          ImageAnnotation.rect(
            id: 'ann-geo',
            normalizedRect: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
            note: '修复眼睛',
          ),
        ],
      );
      repository.addImageForTesting(annotated);

      final tool = NovelAiInpaintGeometryTool(repository: repository);
      final result = await tool.execute('c_geo_ann', {
        'annotation_id': 'ann-geo',
      });
      expect(result.isError, isFalse);
      // 实际 1024px: 0.1~0.3 → (102, 102) 205x205；若误用假参数 512 会得到 (51, 51) 103x103
      expect(result.content, contains('目标选区: (102, 102) 205x205 px'));
      expect(result.content, contains('原图尺寸: 1024x1024'));
    });

    test('NovelAiInpaintGeometryTool 缺少 rect 与 annotation_id 时报错', () async {
      final tool = NovelAiInpaintGeometryTool(repository: repository);
      final result = await tool.execute('c_geo_missing', {'image_index': 0});
      expect(result.isError, isTrue);
      expect(result.content, contains('缺少 rect 或 annotation_id'));
    });

    test('NovelAiInpaintGeometryTool 百分比/像素 rect 自动换算 (批注坐标系互通)', () async {
      final tool = NovelAiInpaintGeometryTool(repository: repository);

      // 百分比坐标 (add_image_annotation 体系)：[ymin=25%, xmin=50%, ymax=50%, xmax=75%]
      final pct = await tool.execute('c_geo_pct', {
        'rect': [25.0, 50.0, 50.0, 75.0],
        'image_index': 0,
      });
      expect(pct.isError, isFalse);
      expect(pct.content, contains('百分比 0~100'));
      // 1024px 实际图：选区 left=512, top=256, 256x256
      expect(pct.content, contains('目标选区: (512, 256) 256x256 px'));

      // 像素对象坐标 (view_image_annotations 体系)：{left, top, right, bottom}
      final px = await tool.execute('c_geo_px', {
        'rect': {'left': 512, 'top': 256, 'right': 768, 'bottom': 512},
        'image_index': 0,
      });
      expect(px.isError, isFalse);
      expect(px.content, contains('像素'));
      expect(px.content, contains('目标选区: (512, 256) 256x256 px'));
    });
  });
}
