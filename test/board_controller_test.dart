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

  group('BoardController 局部通知与宿主契约', () {
    test('通知边界：画板内部变更仅局部通知，外壳切换同步宿主广播，视口更新不广播', () {
      final host = _FakeBoardHost();
      final controller = BoardController(
        host: host,
        repository: NovelAiRepository(),
      );
      var localNotifyCount = 0;
      controller.addListener(() => localNotifyCount++);

      controller.addNoteNode(text: '通知边界');
      expect(localNotifyCount, 1, reason: '便签变更应触发画板局部通知');
      expect(host.notifyCount, 0, reason: '便签变更不应触发宿主全局广播');

      controller.selectAnnotationId('ann-x');
      expect(localNotifyCount, 2, reason: '选中批注应触发画板局部通知');
      expect(host.notifyCount, 0, reason: '选中批注不应触发宿主全局广播');

      controller.setAnnotatingImage(true);
      expect(localNotifyCount, 3, reason: '切换批注模式应同步触发画板局部通知');
      expect(host.notifyCount, 1, reason: '切换批注模式属于外壳状态，应触发宿主全局广播');

      // 视口矩阵只更新数据并防抖落盘，不触发任何广播
      controller.updateBoardViewport(1.2, 10.0, 20.0);
      expect(localNotifyCount, 3);
      expect(host.notifyCount, 1);
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
      var localNotifyCount = 0;
      controller.addListener(() => localNotifyCount++);

      controller.addNoteNode(text: '第一批');
      expect(localNotifyCount, 1);
      expect(host.notifyCount, 0);

      controller.setAnnotatingImage(true);
      expect(localNotifyCount, 2);
      expect(host.notifyCount, 1);

      controller.dispose();

      // dispose 后的迟到写入：不再触发局部通知或宿主广播 (不抛异常)
      controller.addNoteNode(text: '迟到批次');
      controller.updateBoardViewport(2.0, 1.0, 1.0);
      controller.selectAnnotationId('late');
      controller.setAnnotatingImage(false);
      expect(localNotifyCount, 2, reason: 'dispose 后局部通知必须被 _alive 卫语句拦截');
      expect(host.notifyCount, 1, reason: 'dispose 后宿主广播必须被 _alive 卫语句拦截');
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
