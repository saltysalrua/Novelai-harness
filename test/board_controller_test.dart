import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/ui/features/studio/view_models/board/board_controller.dart';

/// 1x1 纯净有效 PNG 字节
final kControllerTestPngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

NaiGeneratedImage _makeImage(String id) {
  return NaiGeneratedImage(
    id: id,
    bytes: kControllerTestPngBytes,
    params: const NaiGenerationParams(
      prompt: 'masterpiece',
      width: 832,
      height: 1216,
    ),
    seed: 7,
    isOpusFree: true,
    createdAt: DateTime.now(),
  );
}

/// 隔离测试用假宿主：记录全部回调，不引入 StudioViewModel 构造涟漪
class _FakeBoardHost implements BoardControllerHost {
  NaiGeneratedImage? selectedImage;
  final List<String> chatMessages = [];
  int notifyCount = 0;
  bool exitedOtherModes = false;
  bool persistenceEnabled = false;
  String saveDir = '';

  @override
  NaiGeneratedImage? get boardSelectedImage => selectedImage;

  @override
  void onBoardSelectedImageChanged(NaiGeneratedImage image) {
    selectedImage = image;
  }

  @override
  Future<Uint8List?> ensureBoardImageLoaded(NaiGeneratedImage image) async =>
      image.bytes;

  @override
  Future<void> sendChatMessage(
    String text, {
    List<AgentMessageImage>? images,
  }) async {
    chatMessages.add(text);
  }

  @override
  void exitOtherCanvasEditModes() {
    exitedOtherModes = true;
  }

  @override
  void onBoardStatus(String message) {}

  @override
  bool get boardImagePersistenceEnabled => persistenceEnabled;

  @override
  String get boardSaveDirectory => saveDir;

  @override
  void requestGlobalNotify() {
    notifyCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardController 隔离用例 (阶段 4D 试点契约)', () {
    test('通知边界：状态变更借用宿主广播，视口更新不广播', () {
      final host = _FakeBoardHost();
      final controller = BoardController(
        host: host,
        repository: NovelAiRepository(),
      );

      controller.addNoteNode(text: '通知边界');
      expect(host.notifyCount, 1, reason: '便签变更应经宿主全局广播');

      controller.selectAnnotationId('ann-x');
      expect(host.notifyCount, 2, reason: '选中批注应经宿主全局广播');

      // 视口矩阵只更新数据并防抖落盘，不触发任何广播 (决策门 §4-3 契约)
      controller.updateBoardViewport(1.2, 10.0, 20.0);
      expect(host.notifyCount, 2);
      expect(controller.boardData.viewScale, 1.2);
      expect(controller.boardData.viewTx, 10.0);
      expect(controller.boardData.viewTy, 20.0);

      controller.dispose();
    });

    test('dispose 迟到写入防护：广播与宿主回调被卫语句拦截', () {
      final host = _FakeBoardHost();
      final controller = BoardController(
        host: host,
        repository: NovelAiRepository(),
      );

      controller.addNoteNode(text: '第一批');
      expect(host.notifyCount, 1);
      controller.dispose();

      // dispose 后的迟到写入：不再触碰宿主 (不抛异常、不广播)
      controller.addNoteNode(text: '迟到批次');
      expect(host.notifyCount, 1, reason: 'dispose 后广播必须被 _alive 卫语句拦截');
      controller.updateBoardViewport(2.0, 1.0, 1.0);
      controller.selectAnnotationId('late');
      expect(host.notifyCount, 1);
    });

    test('sendChatMessage 回调注入：批注汇总消息经宿主发送', () async {
      final host = _FakeBoardHost();
      final controller = BoardController(
        host: host,
        repository: NovelAiRepository(),
      );

      controller.addNoteNode(text: '裙子改成红色');
      controller.addNoteNode(text: '背景换成星空');

      await controller.sendAnnotationsToChat();

      expect(host.chatMessages, hasLength(1));
      expect(host.chatMessages.single, contains('画板视觉批注'));
      expect(host.chatMessages.single, contains('裙子改成红色'));
      expect(host.chatMessages.single, contains('背景换成星空'));
      expect(controller.isAnnotatingImage, isFalse, reason: '发送后应退出批注模式');

      controller.dispose();
    });

    test('setAnnotatingImage：目标图经宿主回写选中并退出其他编辑模式', () {
      final repo = NovelAiRepository();
      final imgA = _makeImage('img-a');
      final imgB = _makeImage('img-b');
      repo.addImageForTesting(imgA);
      repo.addImageForTesting(imgB);

      final host = _FakeBoardHost()..selectedImage = imgA;
      final controller = BoardController(host: host, repository: repo);

      controller.setAnnotatingImage(true, targetImageId: 'img-b');
      expect(controller.isAnnotatingImage, isTrue);
      expect(host.selectedImage?.id, 'img-b', reason: '目标图应经宿主回写选中');
      expect(host.exitedOtherModes, isTrue, reason: '进入批注应退出其他画布编辑模式');
      expect(controller.boardData.imageNodes.first.isMain, isTrue);
      expect(controller.boardData.imageNodes.first.image.id, 'img-b');

      controller.dispose();
    });

    test('dispose 立即冲刷布局落盘 (不等防抖定时器)', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nai_board_controller_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final host = _FakeBoardHost()
        ..persistenceEnabled = true
        ..saveDir = tempDir.path;
      final controller = BoardController(
        host: host,
        repository: NovelAiRepository(),
      );

      controller.addNoteNode(text: '落盘验证');
      // dispose：取消防抖 (600ms) 并立即落盘一次 (对齐旧宿主 dispose 契约)
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        File('${tempDir.path}/canvas_board.json').existsSync(),
        isTrue,
        reason: 'dispose 应立即冲刷画布布局，而非等待防抖定时器',
      );
    });
  });
}
